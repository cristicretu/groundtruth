// OccupancyGrid.swift
// Tesla-style occupancy grid - the foundation of scene understanding
// "Don't ask what it is, ask if space is occupied"
import simd
import ARKit

// Cell state - what we know about each grid cell
enum CellState: UInt8, Codable {
    case unknown = 0    // Not scanned yet
    case free = 1       // Can walk here
    case occupied = 2   // Something is here (obstacle)
    case step = 3       // 5-20cm elevation change (warn but walkable)
    case curb = 4       // >20cm elevation change (heavy warning)
    case ramp = 5       // Gradual slope (<10°)
    case stairs = 6     // Repeating steps
    case dropoff = 7    // Dangerous drop (>30cm down)
}

// Single grid cell with elevation data
struct GridCell: Codable {
    var state: CellState = .unknown
    var elevation: Float = 0        // Height relative to user floor (meters)
    var confidence: UInt8 = 0       // 0-255, how sure are we
    var hitCount: UInt16 = 0        // How many points hit this cell
    var minHeight: Float = .infinity
    var maxHeight: Float = -.infinity
    
    var heightRange: Float {
        hitCount > 0 ? maxHeight - minHeight : 0
    }
    
    var isValid: Bool { hitCount >= 3 }

    // Floor samples define the walking surface (minHeight).
    mutating func addFloorPoint(height: Float) {
        minHeight = min(minHeight, height)
        // If we have no max yet, keep it at least floor height.
        if maxHeight == -.infinity { maxHeight = height }
        hitCount += 1
        confidence = UInt8(min(255, Int(confidence) + 10))
    }

    // Obstacle samples define occupancy above the floor (maxHeight).
    mutating func addObstaclePoint(height: Float) {
        maxHeight = max(maxHeight, height)
        hitCount += 1
        confidence = UInt8(min(255, Int(confidence) + 10))
    }
    
    mutating func reset() {
        state = .unknown
        elevation = 0
        confidence = 0
        hitCount = 0
        minHeight = .infinity
        maxHeight = -.infinity
    }
}

// The occupancy grid - 2D top-down view of the world
struct OccupancyGrid: Codable {
    // Grid parameters (from GridConfig)
    let cellSize: Float         // Meters per cell
    let gridSize: Int           // Cells per side
    
    // Grid data
    var cells: [[GridCell]]
    
    // Origin in world coordinates (center of grid)
    var originX: Float = 0
    var originZ: Float = 0
    
    // User position in grid coordinates
    var userGridX: Int = 0
    var userGridZ: Int = 0
    var userHeading: Float = 0  // Radians
    
    // Floor reference
    var floorHeight: Float = 0
    
    // Stats
    var validCellCount: Int = 0
    var obstacleCellCount: Int = 0
    var stepCellCount: Int = 0
    
    // Initialize with size (defaults from GridConfig)
    init(cellSize: Float = GridConfig.cellSize, gridSize: Int = GridConfig.gridSize) {
        self.cellSize = cellSize
        self.gridSize = gridSize
        self.cells = Array(
            repeating: Array(repeating: GridCell(), count: gridSize),
            count: gridSize
        )
    }
    
    // Clear all cells
    mutating func clear() {
        for x in 0..<gridSize {
            for z in 0..<gridSize {
                cells[x][z].reset()
            }
        }
        validCellCount = 0
        obstacleCellCount = 0
        stepCellCount = 0
    }
    
    // Convert world position to grid indices
    func worldToGrid(_ worldX: Float, _ worldZ: Float) -> (x: Int, z: Int)? {
        let halfGrid = GridConfig.halfGrid
        let relX = worldX - originX
        let relZ = worldZ - originZ

        // Stabilize BEV: rotate world into user-forward frame.
        // After this, +Z is "forward" (heading-aligned), +X is "right".
        let (rx, rz) = rotate2D(x: relX, z: relZ, by: -userHeading)
        
        let gridX = Int((rx / cellSize) + halfGrid)
        let gridZ = Int((rz / cellSize) + halfGrid)
        
        guard gridX >= 0 && gridX < gridSize &&
              gridZ >= 0 && gridZ < gridSize else {
            return nil
        }
        
        return (gridX, gridZ)
    }
    
    // Convert grid indices to world position (center of cell)
    func gridToWorld(_ gridX: Int, _ gridZ: Int) -> (x: Float, z: Float) {
        let halfGrid = GridConfig.halfGrid
        let localX = (Float(gridX) - halfGrid + 0.5) * cellSize
        let localZ = (Float(gridZ) - halfGrid + 0.5) * cellSize

        // Inverse of worldToGrid rotation: rotate user-frame back to world.
        let (wx, wz) = rotate2D(x: localX, z: localZ, by: userHeading)
        return (wx + originX, wz + originZ)
    }
    
    // Get cell at world position
    func cellAt(worldX: Float, worldZ: Float) -> GridCell? {
        guard let (gx, gz) = worldToGrid(worldX, worldZ) else { return nil }
        return cells[gx][gz]
    }
    
    // Check if position is safe to walk
    func isSafe(worldX: Float, worldZ: Float) -> Bool {
        guard let cell = cellAt(worldX: worldX, worldZ: worldZ) else {
            return false // Unknown = unsafe
        }
        switch cell.state {
        case .free, .ramp:
            return true
        case .step:
            return true // Warn but allow
        default:
            return false
        }
    }
    
    // Get nearest obstacle in direction
    func nearestObstacle(fromX: Float, fromZ: Float, heading: Float, maxDistance: Float = 5.0) -> Float {
        let stepSize: Float = cellSize
        var distance: Float = 0
        
        let dx = sin(heading) * stepSize
        let dz = cos(heading) * stepSize
        
        var x = fromX
        var z = fromZ
        
        while distance < maxDistance {
            x += dx
            z += dz
            distance += stepSize
            
            if let cell = cellAt(worldX: x, worldZ: z) {
                if cell.state == .occupied || cell.state == .curb || cell.state == .dropoff {
                    return distance
                }
            }
        }
        
        return .infinity
    }
}

// MARK: - Math

@inline(__always)
private func rotate2D(x: Float, z: Float, by angle: Float) -> (Float, Float) {
    let c = cos(angle)
    let s = sin(angle)
    // Standard 2D rotation in XZ plane
    return (x * c - z * s, x * s + z * c)
}

// Builder - constructs occupancy grid from ARKit mesh
final class OccupancyGridBuilder {
    
    private var grid: OccupancyGrid
    private let lock = NSLock()
    
    // Reusable buffer for floor height calculation (avoid alloc per frame)
    private var floorHeightBuffer: [Float] = []
    
    init(cellSize: Float = GridConfig.cellSize, gridSize: Int = GridConfig.gridSize) {
        grid = OccupancyGrid(cellSize: cellSize, gridSize: gridSize)
        floorHeightBuffer.reserveCapacity(200)
    }
    
    // Build grid from ARKit mesh anchors
    func build(
        from anchors: [ARMeshAnchor],
        userPosition: simd_float3,
        userHeading: Float,
        maxDistance: Float = GridConfig.maxDistance
    ) -> OccupancyGrid {
        lock.lock()
        defer { lock.unlock() }
        
        // Reset grid each frame (TODO: add decay for temporal filtering later)
        grid.clear()
        grid.originX = userPosition.x
        grid.originZ = userPosition.z
        grid.userHeading = userHeading
        grid.userGridX = grid.gridSize / 2
        grid.userGridZ = grid.gridSize / 2
        
        // First pass: find floor height from classified floor vertices
        floorHeightBuffer.removeAll(keepingCapacity: true)
        
        for anchor in anchors {
            let geometry = anchor.geometry
            let transform = anchor.transform
            guard let classBuffer = geometry.classification else { continue }
            
            let vertexStride = geometry.vertices.stride
            let classStride = classBuffer.stride
            
            // Sample every 8th vertex for speed
            for i in stride(from: 0, to: geometry.vertices.count, by: 8) {
                let classPtr = classBuffer.buffer.contents().advanced(by: i * classStride)
                let classValue = classPtr.assumingMemoryBound(to: UInt8.self).pointee
                
                if ARMeshClassification(rawValue: Int(classValue)) == .floor {
                    let vertPtr = geometry.vertices.buffer.contents().advanced(by: i * vertexStride)
                    let localV = vertPtr.assumingMemoryBound(to: simd_float3.self).pointee
                    let worldV = simd_make_float3(transform * simd_float4(localV, 1))
                    
                    let dx = worldV.x - userPosition.x
                    let dz = worldV.z - userPosition.z
                    if dx*dx + dz*dz < 4.0 { // Within 2m of user
                        floorHeightBuffer.append(worldV.y)
                    }
                }
            }
        }
        
        // Use median floor height
        if floorHeightBuffer.count > ProcessingConfig.minFloorSamples {
            floorHeightBuffer.sort()
            grid.floorHeight = floorHeightBuffer[floorHeightBuffer.count / 2]
        } else {
            grid.floorHeight = userPosition.y - 1.6 // Default: user height
        }
        
        // Second pass: populate grid cells
        for anchor in anchors {
            let geometry = anchor.geometry
            let transform = anchor.transform
            let vertexBuffer = geometry.vertices
            let vertexStride = vertexBuffer.stride
            let classBuffer = geometry.classification
            let classStride = classBuffer?.stride ?? 1
            
            // Check if anchor is within range
            let anchorPos = simd_make_float3(transform.columns.3)
            let dx = anchorPos.x - userPosition.x
            let dz = anchorPos.z - userPosition.z
            if dx*dx + dz*dz > (maxDistance + 2) * (maxDistance + 2) { continue }
            
            // Sample vertices (every 2nd for balance of speed/detail)
            for i in stride(from: 0, to: vertexBuffer.count, by: 2) {
                let ptr = vertexBuffer.buffer.contents().advanced(by: i * vertexStride)
                let localVertex = ptr.assumingMemoryBound(to: simd_float3.self).pointee
                let world = simd_make_float3(transform * simd_float4(localVertex, 1))
                
                // Check distance
                let relX = world.x - grid.originX
                let relZ = world.z - grid.originZ
                let dist = sqrt(relX * relX + relZ * relZ)
                guard dist <= maxDistance else { continue }
                
                // Convert to grid indices
                guard let (gridX, gridZ) = grid.worldToGrid(world.x, world.z) else { continue }

                // Use classification to avoid mixing floor+wall+ceiling in same cell.
                // This is the main fix for false \"everything is an obstacle\".
                let relYToFloor = world.y - grid.floorHeight
                var isFloorSample = false
                var isObstacleSample = false

                if let cb = classBuffer {
                    let classPtr = cb.buffer.contents().advanced(by: i * classStride)
                    let raw = classPtr.assumingMemoryBound(to: UInt8.self).pointee
                    let cls = ARMeshClassification(rawValue: Int(raw)) ?? .none

                    switch cls {
                    case .floor:
                        isFloorSample = true
                    case .wall, .door, .window, .table, .seat:
                        // These are obstacles for walking.
                        isObstacleSample = true
                    case .ceiling:
                        // Ceiling shouldn't poison ground occupancy.
                        isObstacleSample = false
                        isFloorSample = false
                    default:
                        // Unknown: fall back to height relative to floor.
                        if abs(relYToFloor) < 0.20 { isFloorSample = true }
                        else if relYToFloor > 0.20 && relYToFloor < 2.0 { isObstacleSample = true }
                    }
                } else {
                    // No classification: fall back to height relative to floor.
                    if abs(relYToFloor) < 0.20 { isFloorSample = true }
                    else if relYToFloor > 0.20 && relYToFloor < 2.0 { isObstacleSample = true }
                }

                if isFloorSample {
                    grid.cells[gridX][gridZ].addFloorPoint(height: world.y)
                } else if isObstacleSample {
                    grid.cells[gridX][gridZ].addObstaclePoint(height: world.y)
                }
            }
        }
        
        // Third pass: classify cells based on floor vs obstacle height.
        // IMPORTANT: Don't try to infer steps/curbs here. That comes from neighbor analysis.
        var validCount = 0
        var obstacleCount = 0
        var stepCount = 0
        
        for x in 0..<grid.gridSize {
            for z in 0..<grid.gridSize {
                var cell = grid.cells[x][z]
                
                // Require a floor estimate; otherwise we don't know if the space is walkable.
                guard cell.isValid, cell.minHeight.isFinite else { continue }
                
                validCount += 1
                
                // Calculate elevation relative to floor
                let elevation = cell.minHeight - grid.floorHeight
                cell.elevation = elevation
                
                // Obstacle height above local floor.
                let obstacleHeight = max(0, cell.maxHeight - cell.minHeight)
                if obstacleHeight > 0.25 {
                    cell.state = .occupied
                    obstacleCount += 1
                } else {
                    cell.state = .free
                }
                
                grid.cells[x][z] = cell
            }
        }
        
        grid.validCellCount = validCount
        grid.obstacleCellCount = obstacleCount
        grid.stepCellCount = stepCount
        
        return grid
    }
    
    // Get current grid (thread-safe copy)
    func getGrid() -> OccupancyGrid {
        lock.lock()
        defer { lock.unlock() }
        return grid
    }
}

// Extension for streaming - compact format
extension OccupancyGrid {
    
    // Encode to compact format for streaming
    // Returns: [state (1 byte), elevation (1 byte as cm)] per cell
    func toCompactData() -> Data {
        var data = Data()
        data.reserveCapacity(gridSize * gridSize * 2)
        
        for z in 0..<gridSize {
            for x in 0..<gridSize {
                let cell = cells[x][z]
                data.append(cell.state.rawValue)
                
                // Elevation as signed byte (cm), clamped to -128...127
                let elevationCm = Int8(clamping: Int(cell.elevation * 100))
                data.append(UInt8(bitPattern: elevationCm))
            }
        }
        
        return data
    }
    
    // Decode from compact format
    static func fromCompactData(_ data: Data, gridSize: Int, cellSize: Float) -> OccupancyGrid? {
        guard data.count == gridSize * gridSize * 2 else { return nil }
        
        var grid = OccupancyGrid(cellSize: cellSize, gridSize: gridSize)
        var index = 0
        
        for z in 0..<gridSize {
            for x in 0..<gridSize {
                let stateRaw = data[index]
                let elevationCm = Int8(bitPattern: data[index + 1])
                
                grid.cells[x][z].state = CellState(rawValue: stateRaw) ?? .unknown
                grid.cells[x][z].elevation = Float(elevationCm) / 100.0
                
                index += 2
            }
        }
        
        return grid
    }
}
