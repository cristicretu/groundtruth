// OccupancyGrid.swift
// Tesla-style occupancy grid - the foundation of scene understanding
// "Don't ask what it is, ask if space is occupied"
import simd

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

    var isValid: Bool { hitCount >= ProcessingConfig.minHitCount }

    // Floor samples define the walking surface (minHeight).
    mutating func addFloorPoint(height: Float) {
        minHeight = min(minHeight, height)
        // If we have no max yet, keep it at least floor height.
        if maxHeight == -.infinity { maxHeight = height }
        hitCount += 1
        confidence = min(TemporalConfig.maxConfidence, confidence &+ TemporalConfig.observationBoost)
    }

    // Obstacle samples define occupancy above the floor (maxHeight).
    mutating func addObstaclePoint(height: Float) {
        maxHeight = max(maxHeight, height)
        hitCount += 1
        confidence = min(TemporalConfig.maxConfidence, confidence &+ TemporalConfig.observationBoost)
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
// Storage is WORLD-ALIGNED (no heading rotation). Heading rotation is applied at output time.
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

    // Convert world position to grid indices (world-aligned, no rotation)
    func worldToGrid(_ worldX: Float, _ worldZ: Float) -> (x: Int, z: Int)? {
        let halfGrid = Float(gridSize) / 2.0
        let relX = worldX - originX
        let relZ = worldZ - originZ

        let gridX = Int((relX / cellSize) + halfGrid)
        let gridZ = Int((relZ / cellSize) + halfGrid)

        guard gridX >= 0, gridX < gridSize,
              gridZ >= 0, gridZ < gridSize else {
            return nil
        }

        return (gridX, gridZ)
    }

    // Convert grid indices to world position (center of cell)
    func gridToWorld(_ gridX: Int, _ gridZ: Int) -> (x: Float, z: Float) {
        let halfGrid = Float(gridSize) / 2.0
        let localX = (Float(gridX) - halfGrid + 0.5) * cellSize
        let localZ = (Float(gridZ) - halfGrid + 0.5) * cellSize
        return (localX + originX, localZ + originZ)
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

// MARK: - Multi-source update methods

extension OccupancyGrid {
    /// Update user pose and trigger re-centering if needed
    mutating func updateUserPose(position: simd_float3, heading: Float) {
        userHeading = heading
        let distFromCenter = max(abs(position.x - originX), abs(position.z - originZ))
        let edgeThreshold = (Float(gridSize) * cellSize / 2.0) * (1.0 - GridConfig.recenterEdgeMargin)
        if distFromCenter > edgeThreshold {
            recenter(to: position)
        }
    }

    /// Decay confidence over time; reset cells that fall below threshold
    mutating func applyDecay(deltaTime: Float) {
        let decayFactor = pow(TemporalConfig.confidenceDecay, deltaTime * 60.0)
        for x in 0..<gridSize {
            for z in 0..<gridSize {
                if cells[x][z].confidence > 0 {
                    let newConf = Float(cells[x][z].confidence) * decayFactor
                    if newConf < Float(TemporalConfig.minConfidence) {
                        cells[x][z].reset()
                    } else {
                        cells[x][z].confidence = UInt8(newConf)
                    }
                }
            }
        }
    }

    /// Project a detected object into grid cells
    mutating func updateFromDetection(bearing: Float, distance: Float, width: Float,
                                       type: DetectedObjectType, confidence: Float) {
        let worldX = originX + sin(bearing) * distance
        let worldZ = originZ + cos(bearing) * distance
        let halfWidth = width / 2.0
        let perpBearing = bearing + .pi / 2.0

        // Mark a rectangular region perpendicular to the bearing
        let steps = max(1, Int(halfWidth / cellSize))
        for s in -steps...steps {
            let offset = Float(s) * cellSize
            let cx = worldX + sin(perpBearing) * offset
            let cz = worldZ + cos(perpBearing) * offset
            guard let (gx, gz) = worldToGrid(cx, cz) else { continue }
            cells[gx][gz].state = .occupied
            let boost = UInt8(clamping: Int(confidence * Float(TemporalConfig.observationBoost)))
            cells[gx][gz].confidence = min(TemporalConfig.maxConfidence, cells[gx][gz].confidence &+ boost)
            cells[gx][gz].hitCount += 1
        }
    }

    /// Single-cell update from monocular depth
    mutating func updateFromDepthSample(bearing: Float, distance: Float, isGround: Bool) {
        let worldX = originX + sin(bearing) * distance
        let worldZ = originZ + cos(bearing) * distance
        guard let (gx, gz) = worldToGrid(worldX, worldZ) else { return }
        if isGround {
            cells[gx][gz].addFloorPoint(height: floorHeight)
        } else {
            cells[gx][gz].addObstaclePoint(height: floorHeight + ElevationConfig.obstacleHeight)
        }
    }

    /// Shift grid so the new position is at center
    private mutating func recenter(to position: simd_float3) {
        let newOriginX = position.x
        let newOriginZ = position.z
        let shiftX = Int((newOriginX - originX) / cellSize)
        let shiftZ = Int((newOriginZ - originZ) / cellSize)

        var newCells = Array(repeating: Array(repeating: GridCell(), count: gridSize), count: gridSize)
        for x in 0..<gridSize {
            for z in 0..<gridSize {
                let srcX = x + shiftX
                let srcZ = z + shiftZ
                if srcX >= 0, srcX < gridSize, srcZ >= 0, srcZ < gridSize {
                    newCells[x][z] = cells[srcX][srcZ]
                }
            }
        }
        cells = newCells
        originX = newOriginX
        originZ = newOriginZ
    }
}

// MARK: - Math

@inline(__always)
func rotate2D(x: Float, z: Float, by angle: Float) -> (Float, Float) {
    let c = cos(angle)
    let s = sin(angle)
    // Standard 2D rotation in XZ plane
    return (x * c - z * s, x * s + z * c)
}

// Extension for streaming - compact format
extension OccupancyGrid {

    // Encode to compact format for streaming
    // Applies heading rotation at output time (grid storage is world-aligned)
    func toCompactData() -> Data {
        var data = Data()
        data.reserveCapacity(gridSize * gridSize * 2)
        let halfGrid = Float(gridSize) / 2.0

        for z in 0..<gridSize {
            for x in 0..<gridSize {
                // Output cell in heading-aligned space → convert to world → look up
                let localX = (Float(x) - halfGrid + 0.5) * cellSize
                let localZ = (Float(z) - halfGrid + 0.5) * cellSize
                // Rotate from heading-aligned to world
                let (wx, wz) = rotate2D(x: localX, z: localZ, by: userHeading)
                let worldX = wx + originX
                let worldZ = wz + originZ

                if let (gx, gz) = worldToGrid(worldX, worldZ) {
                    let cell = cells[gx][gz]
                    data.append(cell.state.rawValue)
                    let elevationCm = Int8(clamping: Int(cell.elevation * 100))
                    data.append(UInt8(bitPattern: elevationCm))
                } else {
                    data.append(CellState.unknown.rawValue)
                    data.append(0)
                }
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
