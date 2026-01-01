// Mesh.swift
// Mesh extraction utilities for point cloud and mesh data
import ARKit
import simd

// Point for streaming to Mac visualization (legacy support)
struct Point3D: Codable {
    var x: Float  // relative to user
    var y: Float  // height relative to floor
    var z: Float  // relative to user
    var c: UInt8  // category: 0=floor, 1=obstacle, 2=wall
}

// Full mesh data for detailed visualization (legacy support)
struct MeshData: Codable {
    var vertices: [Float]   // x,y,z,x,y,z,...
    var indices: [UInt32]   // triangle indices
    var classes: [UInt8]    // per-vertex classification
}

// Mesh extraction utilities
struct MeshExtractor {
    
    // Extract point cloud using ARKit scene classification
    static func extractPointCloud(
        from anchors: [ARMeshAnchor],
        userPosition: simd_float3,
        floorY: Float,
        maxPoints: Int = 5000,
        maxDistance: Float = 5.0
    ) -> [Point3D] {
        var allPoints: [Point3D] = []
        allPoints.reserveCapacity(maxPoints)

        // First pass: find floor height from classified floor vertices
        var floorHeights: [Float] = []
        for anchor in anchors {
            let geo = anchor.geometry
            let transform = anchor.transform
            guard let classBuffer = geo.classification else { continue }

            let vertexStride = geo.vertices.stride
            let classStride = classBuffer.stride

            for i in stride(from: 0, to: geo.vertices.count, by: 8) {
                let classPtr = classBuffer.buffer.contents().advanced(by: i * classStride)
                let classValue = classPtr.assumingMemoryBound(to: UInt8.self).pointee
                let classification = ARMeshClassification(rawValue: Int(classValue)) ?? .none

                if classification == .floor {
                    let vertPtr = geo.vertices.buffer.contents().advanced(by: i * vertexStride)
                    let localV = vertPtr.assumingMemoryBound(to: simd_float3.self).pointee
                    let worldV = simd_make_float3(transform * simd_float4(localV, 1))

                    let dx = worldV.x - userPosition.x
                    let dz = worldV.z - userPosition.z
                    if dx*dx + dz*dz < 4.0 { // within 2m
                        floorHeights.append(worldV.y)
                    }
                }
            }
        }

        // Use median floor height, fallback to passed floorY
        let actualFloorY: Float
        if floorHeights.count > 10 {
            floorHeights.sort()
            actualFloorY = floorHeights[floorHeights.count / 2]
        } else {
            actualFloorY = floorY
        }

        // Count total vertices for sampling
        var totalVertices = 0
        for anchor in anchors { totalVertices += anchor.geometry.vertices.count }
        let stride = max(1, totalVertices / maxPoints)
        var vertexIndex = 0

        // Second pass: extract points with classification
        for anchor in anchors {
            let geo = anchor.geometry
            let transform = anchor.transform
            let classBuffer = geo.classification
            let vertexStride = geo.vertices.stride
            let classStride = classBuffer?.stride ?? 1

            for i in 0..<geo.vertices.count {
                vertexIndex += 1
                guard vertexIndex % stride == 0 else { continue }

                let vertPtr = geo.vertices.buffer.contents().advanced(by: i * vertexStride)
                let localV = vertPtr.assumingMemoryBound(to: simd_float3.self).pointee
                let world = simd_make_float3(transform * simd_float4(localV, 1))

                let relX = world.x - userPosition.x
                let relZ = world.z - userPosition.z
                let relY = world.y - actualFloorY

                let dist = sqrt(relX * relX + relZ * relZ)
                guard dist <= maxDistance else { continue }

                // Get ARKit classification if available
                let category: UInt8
                if let cb = classBuffer {
                    let classPtr = cb.buffer.contents().advanced(by: i * classStride)
                    let classValue = classPtr.assumingMemoryBound(to: UInt8.self).pointee
                    let classification = ARMeshClassification(rawValue: Int(classValue)) ?? .none

                    switch classification {
                    case .floor:
                        category = 0
                    case .wall, .door, .window:
                        category = 2
                    case .ceiling:
                        category = 3
                    case .table, .seat:
                        category = 4
                    default:
                        // fallback to height-based
                        if relY < 0.15 { category = 0 }
                        else if relY < 1.5 { category = 1 }
                        else { category = 2 }
                    }
                } else {
                    // no classification, use height
                    if relY < 0.15 { category = 0 }
                    else if relY < 1.5 { category = 1 }
                    else { category = 2 }
                }

                allPoints.append(Point3D(x: relX, y: relY, z: relZ, c: category))
                if allPoints.count >= maxPoints { break }
            }
            if allPoints.count >= maxPoints { break }
        }

        return allPoints
    }

    // Extract full mesh with triangles for detailed visualization
    static func extractMesh(
        from anchors: [ARMeshAnchor],
        userPosition: simd_float3,
        maxDistance: Float = 5.0
    ) -> MeshData {
        var allVerts: [Float] = []
        var allIndices: [UInt32] = []
        var allClasses: [UInt8] = []

        // First pass: find floor height
        var floorHeights: [Float] = []
        for anchor in anchors {
            let geo = anchor.geometry
            let transform = anchor.transform
            guard let classBuffer = geo.classification else { continue }

            let vertexStride = geo.vertices.stride
            let classStride = classBuffer.stride

            for i in stride(from: 0, to: geo.vertices.count, by: 16) {
                let classPtr = classBuffer.buffer.contents().advanced(by: i * classStride)
                let classValue = classPtr.assumingMemoryBound(to: UInt8.self).pointee
                if ARMeshClassification(rawValue: Int(classValue)) == .floor {
                    let vertPtr = geo.vertices.buffer.contents().advanced(by: i * vertexStride)
                    let localV = vertPtr.assumingMemoryBound(to: simd_float3.self).pointee
                    let worldV = simd_make_float3(transform * simd_float4(localV, 1))
                    let dx = worldV.x - userPosition.x
                    let dz = worldV.z - userPosition.z
                    if dx*dx + dz*dz < 9.0 {
                        floorHeights.append(worldV.y)
                    }
                }
            }
        }

        let floorY: Float
        if floorHeights.count > 10 {
            floorHeights.sort()
            floorY = floorHeights[floorHeights.count / 2]
        } else {
            floorY = userPosition.y - 1.6
        }

        var globalVertexOffset: UInt32 = 0

        for anchor in anchors {
            let geo = anchor.geometry
            let transform = anchor.transform
            let classBuffer = geo.classification

            let vertexStride = geo.vertices.stride
            let classStride = classBuffer?.stride ?? 1
            let faceBuffer = geo.faces
            let faceStride = faceBuffer.bytesPerIndex

            // Check if anchor is within range
            let anchorPos = simd_make_float3(transform.columns.3)
            let dx = anchorPos.x - userPosition.x
            let dz = anchorPos.z - userPosition.z
            if dx*dx + dz*dz > (maxDistance + 2) * (maxDistance + 2) { continue }

            let startVert = allVerts.count / 3

            // Extract vertices
            for i in 0..<geo.vertices.count {
                let vertPtr = geo.vertices.buffer.contents().advanced(by: i * vertexStride)
                let localV = vertPtr.assumingMemoryBound(to: simd_float3.self).pointee
                let world = simd_make_float3(transform * simd_float4(localV, 1))

                let relX = world.x - userPosition.x
                let relZ = world.z - userPosition.z
                let relY = world.y - floorY

                allVerts.append(relX)
                allVerts.append(relY)
                allVerts.append(relZ)

                // Classification
                var cat: UInt8 = 1
                if let cb = classBuffer {
                    let classPtr = cb.buffer.contents().advanced(by: i * classStride)
                    let classValue = classPtr.assumingMemoryBound(to: UInt8.self).pointee
                    let classification = ARMeshClassification(rawValue: Int(classValue)) ?? .none
                    switch classification {
                    case .floor: cat = 0
                    case .wall: cat = 2
                    case .ceiling: cat = 3
                    case .table, .seat: cat = 4
                    case .door: cat = 5
                    case .window: cat = 6
                    default:
                        if relY < 0.15 { cat = 0 }
                        else if relY > 2.0 { cat = 3 }
                        else { cat = 1 }
                    }
                }
                allClasses.append(cat)
            }

            // Extract faces (triangles)
            let faceCount = faceBuffer.count / 3
            for f in 0..<faceCount {
                var idx: [UInt32] = [0, 0, 0]
                for j in 0..<3 {
                    let ptr = faceBuffer.buffer.contents().advanced(by: (f * 3 + j) * faceStride)
                    if faceStride == 4 {
                        idx[j] = ptr.assumingMemoryBound(to: UInt32.self).pointee
                    } else {
                        idx[j] = UInt32(ptr.assumingMemoryBound(to: UInt16.self).pointee)
                    }
                }

                // Get triangle center to check distance
                let i0 = Int(idx[0]), i1 = Int(idx[1]), i2 = Int(idx[2])
                let v0x = allVerts[(startVert + i0) * 3]
                let v0z = allVerts[(startVert + i0) * 3 + 2]
                let v1x = allVerts[(startVert + i1) * 3]
                let v1z = allVerts[(startVert + i1) * 3 + 2]
                let v2x = allVerts[(startVert + i2) * 3]
                let v2z = allVerts[(startVert + i2) * 3 + 2]
                let cx = (v0x + v1x + v2x) / 3
                let cz = (v0z + v1z + v2z) / 3

                if cx*cx + cz*cz <= maxDistance * maxDistance {
                    allIndices.append(globalVertexOffset + idx[0])
                    allIndices.append(globalVertexOffset + idx[1])
                    allIndices.append(globalVertexOffset + idx[2])
                }
            }

            globalVertexOffset += UInt32(geo.vertices.count)
        }

        return MeshData(vertices: allVerts, indices: allIndices, classes: allClasses)
    }
}
