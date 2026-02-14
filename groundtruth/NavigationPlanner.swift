// NavigationPlanner.swift
// Converts SceneUnderstanding into grid updates and computes walking direction.
// No hardcoded object types — the grid only knows free, occupied, surface_change.

import simd

// MARK: - Scene Analysis Input Types

enum DiscontinuityDir {
    case dropaway
    case riseup
}

struct Discontinuity {
    let column: Int
    let bearing: Float
    let relativeDepth: Float
    let magnitude: Float
    let direction: DiscontinuityDir
}

struct SceneUnderstanding {
    let columns: Int
    let traversability: [Float]
    let obstacleDistance: [Float]
    let discontinuities: [Discontinuity]
    let groundPlaneRatio: Float
    let columnBearings: [Float]
}

// MARK: - Navigation Output

struct NavigationOutput {
    var suggestedHeading: Float = 0
    var clearance: Float = .infinity
    var nearestObstacleDistance: Float = .infinity
    var nearestObstacleBearing: Float = 0
    var discontinuityAhead: Discontinuity? = nil
    var groundConfidence: Float = 1.0
    var isPathBlocked: Bool = false
}

// MARK: - Navigation Planner

final class NavigationPlanner {
    var depthScale: Float = 10.0
    var smoothingFactor: Float = 0.3
    var safetyMargin: Float = 0.5

    private var previousHeading: Float = 0

    func update(
        scene: SceneUnderstanding,
        userPosition: simd_float3,
        userHeading: Float,
        deltaTime: Float,
        grid: inout OccupancyGrid
    ) -> NavigationOutput {
        // --- Phase 1: Project scene into grid ---
        projectScene(scene, userPosition: userPosition, userHeading: userHeading, grid: &grid)

        grid.applyDecay(deltaTime: deltaTime)
        grid.updateUserPose(position: userPosition, heading: userHeading)

        // --- Phase 2: Compute heading ---
        let rayCount = 36
        let halfArc: Float = .pi / 2.0  // ±90°
        let maxMarch: Float = 10.0

        var bestScore: Float = -1
        var bestAngle: Float = 0
        var bestClearance: Float = 0

        for i in 0..<rayCount {
            let t = Float(i) / Float(rayCount - 1)
            let angle = -halfArc + t * (2.0 * halfArc)
            let rayHeading = userHeading + angle

            let dx = sin(rayHeading) * grid.cellSize
            let dz = cos(rayHeading) * grid.cellSize

            var x = userPosition.x
            var z = userPosition.z
            var dist: Float = 0
            var clearance: Float = maxMarch
            var stepPenalty: Float = 1.0

            while dist < maxMarch {
                x += dx
                z += dz
                dist += grid.cellSize

                if let cell = grid.cellAt(worldX: x, worldZ: z) {
                    switch cell.state {
                    case .occupied, .curb, .dropoff:
                        clearance = dist
                        break
                    case .step:
                        stepPenalty = min(stepPenalty, 0.7)
                        continue
                    default:
                        continue
                    }
                    break  // hit a blocking cell
                }
            }

            // Reject rays blocked within safety margin
            if clearance <= safetyMargin {
                continue
            }

            let score = clearance * (1.0 - abs(angle) / .pi * 0.5) * stepPenalty
            if score > bestScore {
                bestScore = score
                bestAngle = angle
                bestClearance = clearance
            }
        }

        let isBlocked = bestScore < 0

        // Smooth heading
        let rawHeading = isBlocked ? 0 : bestAngle
        let smoothed = smoothingFactor * rawHeading + (1.0 - smoothingFactor) * previousHeading
        previousHeading = smoothed

        // --- Phase 3: Find nearest threat in forward ±45° ---
        var nearestDist: Float = .infinity
        var nearestBearing: Float = 0
        let threatArc: Float = .pi / 4.0

        for i in 0..<18 {
            let t = Float(i) / 17.0
            let angle = -threatArc + t * (2.0 * threatArc)
            let rayHeading = userHeading + angle

            let dx = sin(rayHeading) * grid.cellSize
            let dz = cos(rayHeading) * grid.cellSize
            var x = userPosition.x
            var z = userPosition.z
            var dist: Float = 0

            while dist < maxMarch {
                x += dx
                z += dz
                dist += grid.cellSize

                if let cell = grid.cellAt(worldX: x, worldZ: z) {
                    if cell.state == .occupied || cell.state == .curb || cell.state == .dropoff {
                        if dist < nearestDist {
                            nearestDist = dist
                            nearestBearing = angle
                        }
                        break
                    }
                }
            }
        }

        // --- Phase 4: Find discontinuity ahead ---
        let forwardDisc = scene.discontinuities
            .filter { abs($0.bearing) < threatArc }
            .min { a, b in
                let da = depthScale / (a.relativeDepth + 0.001)
                let db = depthScale / (b.relativeDepth + 0.001)
                return da < db
            }

        // Ground confidence from traversability
        let groundConfidence = scene.traversability.isEmpty
            ? 0
            : scene.traversability.reduce(0, +) / Float(scene.traversability.count)

        return NavigationOutput(
            suggestedHeading: smoothed,
            clearance: bestClearance,
            nearestObstacleDistance: nearestDist,
            nearestObstacleBearing: nearestBearing,
            discontinuityAhead: forwardDisc,
            groundConfidence: groundConfidence,
            isPathBlocked: isBlocked
        )
    }

    // MARK: - Grid Projection

    private func projectScene(
        _ scene: SceneUnderstanding,
        userPosition: simd_float3,
        userHeading: Float,
        grid: inout OccupancyGrid
    ) {
        // Build a lookup of discontinuities by column
        var discByColumn: [Int: Discontinuity] = [:]
        for d in scene.discontinuities {
            discByColumn[d.column] = d
        }

        for col in 0..<scene.columns {
            guard col < scene.columnBearings.count else { continue }
            let bearing = scene.columnBearings[col]
            let worldBearing = bearing + userHeading

            let sinB = sin(worldBearing)
            let cosB = cos(worldBearing)

            // Project free cells along traversable rays
            if col < scene.traversability.count && scene.traversability[col] > 0.7 {
                let maxDist: Float
                if col < scene.obstacleDistance.count && scene.obstacleDistance[col].isFinite {
                    maxDist = depthScale / (scene.obstacleDistance[col] + 0.001)
                } else {
                    maxDist = 5.0  // default free range
                }

                var dist: Float = 0.5
                while dist < maxDist {
                    let wx = userPosition.x + sinB * dist
                    let wz = userPosition.z + cosB * dist
                    if let (gx, gz) = grid.worldToGrid(wx, wz) {
                        grid.cells[gx][gz].state = .free
                        grid.cells[gx][gz].confidence = min(
                            TemporalConfig.maxConfidence,
                            grid.cells[gx][gz].confidence &+ TemporalConfig.observationBoost
                        )
                        grid.cells[gx][gz].hitCount += 1
                    }
                    dist += grid.cellSize
                }
            }

            // Project obstacle
            if col < scene.obstacleDistance.count && scene.obstacleDistance[col].isFinite {
                let meters = depthScale / (scene.obstacleDistance[col] + 0.001)
                let wx = userPosition.x + sinB * meters
                let wz = userPosition.z + cosB * meters
                if let (gx, gz) = grid.worldToGrid(wx, wz) {
                    grid.cells[gx][gz].state = .occupied
                    grid.cells[gx][gz].confidence = min(
                        TemporalConfig.maxConfidence,
                        grid.cells[gx][gz].confidence &+ TemporalConfig.observationBoost
                    )
                    grid.cells[gx][gz].hitCount += 1
                }
            }

            // Project discontinuity
            if let disc = discByColumn[col] {
                let meters = depthScale / (disc.relativeDepth + 0.001)
                let wx = userPosition.x + sinB * meters
                let wz = userPosition.z + cosB * meters
                if let (gx, gz) = grid.worldToGrid(wx, wz) {
                    if disc.magnitude < 0.3 {
                        grid.cells[gx][gz].state = .step
                    } else if disc.magnitude <= 0.6 {
                        grid.cells[gx][gz].state = .curb
                    } else {
                        grid.cells[gx][gz].state = .dropoff
                    }
                    grid.cells[gx][gz].confidence = min(
                        TemporalConfig.maxConfidence,
                        grid.cells[gx][gz].confidence &+ TemporalConfig.observationBoost
                    )
                    grid.cells[gx][gz].hitCount += 1
                }
            }
        }
    }
}
