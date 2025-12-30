// World.swift
// WorldModel - single source of truth for the environment
import simd

// The world state - immutable snapshot
struct WorldModel {
    let userPosition: simd_float3
    let userHeading: Float  // radians
    let obstacles: [Obstacle]
    let nearestObstacle: Float  // meters, .infinity if clear
    let floorHeight: Float
    let timestamp: Double
    
    struct Obstacle {
        let position: simd_float2  // XZ world coords
        let distance: Float        // from user
        let angle: Float          // relative to user heading (-pi to pi)
        let isCurb: Bool          // height 8-20cm vs >20cm
    }
    
    static let empty = WorldModel(
        userPosition: .zero,
        userHeading: 0,
        obstacles: [],
        nearestObstacle: .infinity,
        floorHeight: 0,
        timestamp: 0
    )
}

// Builds WorldModel from depth points
final class WorldBuilder {
    
    // grid parameters
    private let cellSize: Float = 0.1      // 10cm cells
    private let gridRadius: Int = 50       // 5m radius
    private var gridSize: Int { gridRadius * 2 + 1 }
    
    // the grid - each cell tracks min/max height
    private var cells: [[Cell]]
    private var gridOrigin: simd_float2 = .zero
    
    private struct Cell {
        var minHeight: Float = .infinity
        var maxHeight: Float = -.infinity
        var count: Int = 0
        
        var heightRange: Float {
            count > 0 ? maxHeight - minHeight : 0
        }
        
        var isObstacle: Bool { heightRange > 0.20 }
        var isCurb: Bool { heightRange > 0.08 && heightRange <= 0.20 }
        
        mutating func add(_ height: Float) {
            minHeight = min(minHeight, height)
            maxHeight = max(maxHeight, height)
            count += 1
        }
        
        mutating func reset() {
            minHeight = .infinity
            maxHeight = -.infinity
            count = 0
        }
    }
    
    init() {
        cells = Array(
            repeating: Array(repeating: Cell(), count: gridRadius * 2 + 1),
            count: gridRadius * 2 + 1
        )
    }
    
    // Build world model from points and camera pose
    func update(
        points: [(position: simd_float3, confidence: Int)],
        transform: simd_float4x4,
        timestamp: Double
    ) -> WorldModel {
        
        // extract user position and heading from transform
        let userPos = simd_float3(
            transform.columns.3.x,
            transform.columns.3.y,
            transform.columns.3.z
        )
        
        let forward = simd_float3(
            -transform.columns.2.x,
            0,
            -transform.columns.2.z
        )
        let heading = atan2(forward.x, forward.z)
        
        // recenter grid on user
        gridOrigin = simd_float2(userPos.x, userPos.z)
        
        // reset grid
        for x in 0..<gridSize {
            for z in 0..<gridSize {
                cells[x][z].reset()
            }
        }
        
        // accumulate points into grid
        for point in points {
            let localX = point.position.x - gridOrigin.x
            let localZ = point.position.z - gridOrigin.y
            
            let gridX = Int(localX / cellSize) + gridRadius
            let gridZ = Int(localZ / cellSize) + gridRadius
            
            guard gridX >= 0 && gridX < gridSize &&
                  gridZ >= 0 && gridZ < gridSize else { continue }
            
            cells[gridX][gridZ].add(point.position.y)
        }
        
        // extract obstacles
        var obstacles: [WorldModel.Obstacle] = []
        var nearestDist: Float = .infinity
        var floorSum: Float = 0
        var floorCount: Int = 0
        
        let userXZ = simd_float2(userPos.x, userPos.z)
        
        for x in 0..<gridSize {
            for z in 0..<gridSize {
                let cell = cells[x][z]
                guard cell.count >= 3 else { continue }  // need enough points
                
                let worldX = Float(x - gridRadius) * cellSize + gridOrigin.x
                let worldZ = Float(z - gridRadius) * cellSize + gridOrigin.y
                let cellPos = simd_float2(worldX, worldZ)
                
                let toCell = cellPos - userXZ
                let dist = simd_length(toCell)
                
                // track floor height from non-obstacle cells
                if !cell.isObstacle && !cell.isCurb {
                    floorSum += cell.minHeight
                    floorCount += 1
                }
                
                // detect obstacles and curbs
                if cell.isObstacle || cell.isCurb {
                    // angle relative to user heading
                    let worldAngle = atan2(toCell.x, toCell.y)
                    let relAngle = worldAngle - heading
                    
                    obstacles.append(WorldModel.Obstacle(
                        position: cellPos,
                        distance: dist,
                        angle: relAngle,
                        isCurb: cell.isCurb
                    ))
                    
                    if dist < nearestDist {
                        nearestDist = dist
                    }
                }
            }
        }
        
        let floorHeight = floorCount > 0 ? floorSum / Float(floorCount) : userPos.y - 1.5
        
        return WorldModel(
            userPosition: userPos,
            userHeading: heading,
            obstacles: obstacles,
            nearestObstacle: nearestDist,
            floorHeight: floorHeight,
            timestamp: timestamp
        )
    }
}
