// Mesh.swift
// Build occupancy grid from ARKit mesh - like robotics SLAM
import ARKit
import simd

// Point for streaming to Mac visualization
struct Point3D: Codable {
    var x: Float  // relative to user
    var y: Float  // height relative to floor
    var z: Float  // relative to user
    var c: UInt8  // category: 0=floor, 1=obstacle, 2=wall
}

// 2D occupancy grid - each cell knows floor height + obstacle height
struct OccupancyGrid {
    let cellSize: Float = 0.2  // 20cm cells
    let gridSize: Int = 40     // 40x40 = 8m x 8m area
    
    // Grid data: each cell has [floorHeight, maxHeight]
    // If maxHeight - floorHeight > threshold, it's an obstacle
    var cells: [[Cell]]
    var originX: Float = 0
    var originZ: Float = 0
    
    struct Cell {
        var floorHeight: Float = .infinity
        var maxHeight: Float = -.infinity
        var hitCount: Int = 0
        
        var isValid: Bool { hitCount >= 2 }
        var height: Float { maxHeight - floorHeight }
        var isFloor: Bool { isValid && height < 0.15 }
        var isObstacle: Bool { isValid && height >= 0.15 }
    }
    
    init() {
        cells = Array(repeating: Array(repeating: Cell(), count: gridSize), count: gridSize)
    }
    
    mutating func clear() {
        for x in 0..<gridSize {
            for z in 0..<gridSize {
                cells[x][z] = Cell()
            }
        }
    }
}

struct MeshExtractor {
    
    // Build occupancy grid from mesh anchors
    static func buildOccupancyGrid(
        from anchors: [ARMeshAnchor],
        userPosition: simd_float3,
        maxDistance: Float = 4.0
    ) -> OccupancyGrid {
        var grid = OccupancyGrid()
        grid.originX = userPosition.x
        grid.originZ = userPosition.z
        
        let halfGrid = Float(grid.gridSize) / 2.0
        
        for anchor in anchors {
            let geometry = anchor.geometry
            let transform = anchor.transform
            let vertexBuffer = geometry.vertices
            let vertexCount = vertexBuffer.count
            let vertexStride = vertexBuffer.stride
            
            // Sample vertices (every 4th for speed)
            for i in Swift.stride(from: 0, to: vertexCount, by: 4) {
                let ptr = vertexBuffer.buffer.contents().advanced(by: i * vertexStride)
                let localVertex = ptr.assumingMemoryBound(to: simd_float3.self).pointee
                
                // Transform to world
                let world = simd_make_float3(transform * simd_float4(localVertex, 1))
                
                // Convert to grid coords (relative to user)
                let relX = world.x - grid.originX
                let relZ = world.z - grid.originZ
                
                // Check distance
                let dist = sqrt(relX * relX + relZ * relZ)
                guard dist <= maxDistance else { continue }
                
                // Convert to grid indices
                let gridX = Int((relX / grid.cellSize) + halfGrid)
                let gridZ = Int((relZ / grid.cellSize) + halfGrid)
                
                guard gridX >= 0 && gridX < grid.gridSize &&
                      gridZ >= 0 && gridZ < grid.gridSize else { continue }
                
                // Update cell
                grid.cells[gridX][gridZ].floorHeight = min(grid.cells[gridX][gridZ].floorHeight, world.y)
                grid.cells[gridX][gridZ].maxHeight = max(grid.cells[gridX][gridZ].maxHeight, world.y)
                grid.cells[gridX][gridZ].hitCount += 1
            }
        }
        
        return grid
    }

    // Extract point cloud for 3D visualization
    static func extractPointCloud(
        from anchors: [ARMeshAnchor],
        userPosition: simd_float3,
        floorY: Float,
        maxPoints: Int = 3000,
        maxDistance: Float = 5.0
    ) -> [Point3D] {
        var allPoints: [Point3D] = []
        allPoints.reserveCapacity(maxPoints)

        // Count total vertices to calculate sampling rate
        var totalVertices = 0
        for anchor in anchors {
            totalVertices += anchor.geometry.vertices.count
        }

        // Calculate stride to hit target point count
        let stride = max(1, totalVertices / maxPoints)
        var vertexIndex = 0

        for anchor in anchors {
            let geometry = anchor.geometry
            let transform = anchor.transform
            let vertexBuffer = geometry.vertices
            let vertexCount = vertexBuffer.count
            let vertexStride = vertexBuffer.stride

            for i in 0..<vertexCount {
                vertexIndex += 1
                guard vertexIndex % stride == 0 else { continue }

                let ptr = vertexBuffer.buffer.contents().advanced(by: i * vertexStride)
                let localVertex = ptr.assumingMemoryBound(to: simd_float3.self).pointee

                // Transform to world coords
                let world = simd_make_float3(transform * simd_float4(localVertex, 1))

                // Convert to user-relative coords
                let relX = world.x - userPosition.x
                let relZ = world.z - userPosition.z
                let relY = world.y - floorY  // height above floor

                // Distance check
                let dist = sqrt(relX * relX + relZ * relZ)
                guard dist <= maxDistance else { continue }

                // Classify by height
                let category: UInt8
                if relY < 0.15 {
                    category = 0  // floor
                } else if relY < 1.5 {
                    category = 1  // obstacle (furniture, etc)
                } else {
                    category = 2  // wall/ceiling
                }

                allPoints.append(Point3D(x: relX, y: relY, z: relZ, c: category))

                if allPoints.count >= maxPoints { break }
            }

            if allPoints.count >= maxPoints { break }
        }

        return allPoints
    }
}
