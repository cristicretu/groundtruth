// ElevationAnalyzer.swift
// Detect steps, curbs, ramps, and stairs from elevation data
// Pure geometry - no ML needed
import simd
import Foundation

// Elevation change types
enum ElevationChangeType: UInt8, Codable {
    case none = 0
    case stepUp = 1      // 5-20cm up
    case stepDown = 2    // 5-20cm down
    case curbUp = 3      // >20cm up
    case curbDown = 4    // >20cm down
    case rampUp = 5      // Gradual upward slope
    case rampDown = 6    // Gradual downward slope
    case stairs = 7      // Repeating steps
    case dropoff = 8     // Dangerous drop (>30cm)
}

// Detected elevation change
struct ElevationChange: Codable {
    let type: ElevationChangeType
    let position: SIMD2<Float>      // World XZ position
    let distance: Float             // Distance from user
    let angle: Float                // Angle relative to user heading
    let heightChange: Float         // Meters (positive = up, negative = down)
    let confidence: Float           // 0-1
    
    var isWarning: Bool {
        switch type {
        case .stepUp, .stepDown, .rampUp, .rampDown:
            return true
        default:
            return false
        }
    }
    
    var isDanger: Bool {
        switch type {
        case .curbUp, .curbDown, .dropoff:
            return true
        default:
            return false
        }
    }
}

// Elevation thresholds (meters)
struct ElevationThresholds {
    static let stepMin: Float = 0.05     // 5cm minimum to be a step
    static let stepMax: Float = 0.20     // 20cm max for step (above = curb)
    static let curbMin: Float = 0.20     // 20cm minimum for curb
    static let dropoff: Float = 0.30     // 30cm = dangerous drop
    static let rampMaxSlope: Float = 0.15 // ~8.5° max slope for ramp
    static let stairStepSize: Float = 0.18 // ~18cm typical stair step
    static let stairTolerance: Float = 0.03 // ±3cm for stair detection
}

// Analyzer for elevation changes
final class ElevationAnalyzer {
    
    // Analyze grid for elevation changes relative to user
    static func analyze(
        grid: OccupancyGrid,
        userHeading: Float,
        maxDistance: Float = 5.0
    ) -> [ElevationChange] {
        var changes: [ElevationChange] = []
        
        let centerX = grid.gridSize / 2
        let centerZ = grid.gridSize / 2
        let maxCells = Int(maxDistance / grid.cellSize)
        
        // Scan in a circular pattern from user
        for dx in -maxCells...maxCells {
            for dz in -maxCells...maxCells {
                let dist = sqrt(Float(dx * dx + dz * dz)) * grid.cellSize
                guard dist <= maxDistance && dist > 0.5 else { continue } // Skip very close
                
                let x = centerX + dx
                let z = centerZ + dz
                
                guard x >= 1 && x < grid.gridSize - 1 &&
                      z >= 1 && z < grid.gridSize - 1 else { continue }
                
                let cell = grid.cells[x][z]
                guard cell.state != .unknown else { continue }
                
                // Check neighbors for elevation transitions
                if let change = detectTransition(grid: grid, x: x, z: z, userHeading: userHeading) {
                    changes.append(change)
                }
            }
        }
        
        // Sort by distance
        changes.sort { $0.distance < $1.distance }
        
        // Merge nearby changes
        return mergeNearbyChanges(changes, threshold: grid.cellSize * 3)
    }
    
    // Detect elevation transition at a cell
    private static func detectTransition(
        grid: OccupancyGrid,
        x: Int,
        z: Int,
        userHeading: Float
    ) -> ElevationChange? {
        let cell = grid.cells[x][z]
        guard cell.isValid else { return nil }
        
        // Get neighbor elevations
        let neighbors = [
            (x-1, z), (x+1, z), (x, z-1), (x, z+1),  // Cardinals
            (x-1, z-1), (x+1, z-1), (x-1, z+1), (x+1, z+1)  // Diagonals
        ]
        
        var maxDiff: Float = 0
        var diffDirection: Float = 0 // Positive = step up, negative = step down
        
        for (nx, nz) in neighbors {
            guard nx >= 0 && nx < grid.gridSize &&
                  nz >= 0 && nz < grid.gridSize else { continue }
            
            let neighbor = grid.cells[nx][nz]
            guard neighbor.isValid else { continue }
            
            let diff = cell.elevation - neighbor.elevation
            if abs(diff) > abs(maxDiff) {
                maxDiff = diff
                diffDirection = diff
            }
        }
        
        // Check if this is a significant transition
        let absDiff = abs(maxDiff)
        guard absDiff >= ElevationThresholds.stepMin else { return nil }
        
        // Determine type
        let type: ElevationChangeType
        if absDiff >= ElevationThresholds.dropoff && diffDirection < 0 {
            type = .dropoff
        } else if absDiff >= ElevationThresholds.curbMin {
            type = diffDirection > 0 ? .curbUp : .curbDown
        } else {
            type = diffDirection > 0 ? .stepUp : .stepDown
        }
        
        // Calculate position and angle
        let (worldX, worldZ) = grid.gridToWorld(x, z)
        let centerX = grid.gridSize / 2
        let centerZ = grid.gridSize / 2
        let dx = Float(x - centerX) * grid.cellSize
        let dz = Float(z - centerZ) * grid.cellSize
        let distance = sqrt(dx * dx + dz * dz)
        let worldAngle = atan2(dx, dz)
        let relAngle = normalizeAngle(worldAngle - userHeading)
        
        // Confidence based on cell validity
        let confidence = min(1.0, Float(cell.hitCount) / 20.0)
        
        return ElevationChange(
            type: type,
            position: SIMD2<Float>(worldX, worldZ),
            distance: distance,
            angle: relAngle,
            heightChange: diffDirection,
            confidence: confidence
        )
    }
    
    // Detect stairs (repeating step pattern)
    static func detectStairs(
        grid: OccupancyGrid,
        direction: Float, // Heading to check
        maxDistance: Float = 3.0
    ) -> ElevationChange? {
        let stepSize = grid.cellSize
        let dx = sin(direction) * stepSize
        let dz = cos(direction) * stepSize
        
        var x = grid.originX
        var z = grid.originZ
        var lastElevation: Float?
        var stepHeights: [Float] = []
        var distance: Float = 0
        
        while distance < maxDistance {
            x += dx
            z += dz
            distance += stepSize
            
            guard let cell = grid.cellAt(worldX: x, worldZ: z),
                  cell.isValid else { continue }
            
            if let last = lastElevation {
                let diff = cell.elevation - last
                if abs(diff) >= ElevationThresholds.stepMin {
                    stepHeights.append(diff)
                }
            }
            lastElevation = cell.elevation
        }
        
        // Check for repeating pattern (3+ similar steps)
        if stepHeights.count >= 3 {
            let avgStep = stepHeights.reduce(0, +) / Float(stepHeights.count)
            let isConsistent = stepHeights.allSatisfy { 
                abs($0 - avgStep) < ElevationThresholds.stairTolerance 
            }
            
            if isConsistent && abs(avgStep - ElevationThresholds.stairStepSize) < 0.05 {
                return ElevationChange(
                    type: .stairs,
                    position: SIMD2<Float>(grid.originX + dx * 3, grid.originZ + dz * 3),
                    distance: stepSize * 3,
                    angle: 0,
                    heightChange: avgStep * Float(stepHeights.count),
                    confidence: 0.8
                )
            }
        }
        
        return nil
    }
    
    // Merge nearby changes to reduce noise
    private static func mergeNearbyChanges(
        _ changes: [ElevationChange],
        threshold: Float
    ) -> [ElevationChange] {
        var merged: [ElevationChange] = []
        var used = Set<Int>()
        
        for (i, change) in changes.enumerated() {
            guard !used.contains(i) else { continue }
            
            var group = [change]
            
            for (j, other) in changes.enumerated() where j > i && !used.contains(j) {
                let dx = change.position.x - other.position.x
                let dz = change.position.y - other.position.y
                let dist = sqrt(dx * dx + dz * dz)
                
                if dist < threshold && change.type == other.type {
                    group.append(other)
                    used.insert(j)
                }
            }
            
            // Keep the one with highest confidence
            if let best = group.max(by: { $0.confidence < $1.confidence }) {
                merged.append(best)
            }
            
            used.insert(i)
        }
        
        return merged
    }
    
    // Get the most urgent warning for user
    static func getMostUrgent(
        _ changes: [ElevationChange],
        userHeading: Float,
        fovAngle: Float = .pi / 2 // 90° field of view
    ) -> ElevationChange? {
        // Filter to changes in front of user
        let inFront = changes.filter { abs($0.angle) < fovAngle / 2 }
        
        // Priority: dropoff > curb > step, then by distance
        let sorted = inFront.sorted { a, b in
            if a.isDanger != b.isDanger { return a.isDanger }
            if a.isWarning != b.isWarning { return a.isWarning }
            return a.distance < b.distance
        }
        
        return sorted.first
    }
    
    // Normalize angle to -π to π
    private static func normalizeAngle(_ angle: Float) -> Float {
        var a = angle
        while a > .pi { a -= 2 * .pi }
        while a < -.pi { a += 2 * .pi }
        return a
    }
}

// Extension for audio feedback descriptions
extension ElevationChange {
    
    var description: String {
        let directionStr: String
        if abs(angle) < 0.3 {
            directionStr = "ahead"
        } else if angle > 0 {
            directionStr = "to your right"
        } else {
            directionStr = "to your left"
        }
        
        let distanceStr = String(format: "%.1f meters", distance)
        
        switch type {
        case .stepUp:
            return "Step up \(distanceStr) \(directionStr)"
        case .stepDown:
            return "Step down \(distanceStr) \(directionStr)"
        case .curbUp:
            return "Curb \(distanceStr) \(directionStr)"
        case .curbDown:
            return "Drop \(distanceStr) \(directionStr)"
        case .rampUp:
            return "Ramp up \(distanceStr) \(directionStr)"
        case .rampDown:
            return "Ramp down \(distanceStr) \(directionStr)"
        case .stairs:
            return "Stairs \(distanceStr) \(directionStr)"
        case .dropoff:
            return "Warning: dangerous drop \(distanceStr) \(directionStr)"
        case .none:
            return ""
        }
    }
    
    var shortDescription: String {
        switch type {
        case .stepUp: return "STEP UP"
        case .stepDown: return "STEP DOWN"
        case .curbUp: return "CURB"
        case .curbDown: return "DROP"
        case .rampUp: return "RAMP UP"
        case .rampDown: return "RAMP DOWN"
        case .stairs: return "STAIRS"
        case .dropoff: return "DANGER"
        case .none: return ""
        }
    }
}
