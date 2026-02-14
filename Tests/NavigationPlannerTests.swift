import XCTest
@testable import groundtruth
import simd

final class NavigationPlannerTests: XCTestCase {

    private func makeScene(
        columns: Int = 12,
        traversability: [Float]? = nil,
        obstacleDistance: [Float]? = nil,
        discontinuities: [Discontinuity] = [],
        groundPlaneRatio: Float = 0.8
    ) -> SceneUnderstanding {
        let bearings = (0..<columns).map { col -> Float in
            let t = Float(col) / Float(columns - 1)
            return -Float.pi / 3.0 + t * (2.0 * Float.pi / 3.0)  // ±60° spread
        }
        return SceneUnderstanding(
            columns: columns,
            traversability: traversability ?? Array(repeating: 1.0, count: columns),
            obstacleDistance: obstacleDistance ?? Array(repeating: Float.infinity, count: columns),
            discontinuities: discontinuities,
            groundPlaneRatio: groundPlaneRatio,
            columnBearings: bearings
        )
    }

    // MARK: - Test 1: Open field

    func testOpenField_headingStraight_highClearance() {
        let planner = NavigationPlanner()
        var grid = OccupancyGrid(cellSize: 0.1, gridSize: 200)
        let scene = makeScene()

        let result = planner.update(
            scene: scene,
            userPosition: simd_float3(0, 0, 0),
            userHeading: 0,
            deltaTime: 1.0 / 60.0,
            grid: &grid
        )

        XCTAssertEqual(result.suggestedHeading, 0, accuracy: 0.3,
                        "Open field heading should be ~straight ahead")
        XCTAssertGreaterThan(result.clearance, 2.0,
                              "Open field should have high clearance")
        XCTAssertFalse(result.isPathBlocked,
                        "Open field should not be blocked")
        XCTAssertGreaterThan(result.groundConfidence, 0.8,
                              "Full traversability should yield high ground confidence")
    }

    // MARK: - Test 2: Wall on left

    func testWallOnLeft_headingShiftsRight() {
        let planner = NavigationPlanner()
        var grid = OccupancyGrid(cellSize: 0.1, gridSize: 200)

        let columns = 12
        var traversability = Array(repeating: Float(1.0), count: columns)
        var obstacleDistance = Array(repeating: Float.infinity, count: columns)

        // Left half (columns 0-5): wall at ~3m raw depth
        // depthScale=10, so meters = 10/(3+0.001) ≈ 3.33m
        for i in 0..<6 {
            traversability[i] = 0.0
            obstacleDistance[i] = 3.0
        }

        let scene = makeScene(
            columns: columns,
            traversability: traversability,
            obstacleDistance: obstacleDistance
        )

        let result = planner.update(
            scene: scene,
            userPosition: simd_float3(0, 0, 0),
            userHeading: 0,
            deltaTime: 1.0 / 60.0,
            grid: &grid
        )

        XCTAssertGreaterThan(result.suggestedHeading, 0.05,
                              "Heading should shift right (positive) when left is blocked")
        XCTAssertFalse(result.isPathBlocked)
    }

    // MARK: - Test 3: Narrow corridor

    func testNarrowCorridor_headingStraight_narrowClearance() {
        let planner = NavigationPlanner()
        var grid = OccupancyGrid(cellSize: 0.1, gridSize: 200)

        let columns = 12
        var traversability = Array(repeating: Float(0.0), count: columns)
        var obstacleDistance = Array(repeating: Float(1.0), count: columns)  // walls at ~10m/1.001 ≈ 10m... use 0.5 for closer

        // Only center 3 columns (5, 6, 7) are traversable
        for i in 5...7 {
            traversability[i] = 1.0
            obstacleDistance[i] = .infinity
        }

        // Walls on sides at raw depth 0.5 → meters ≈ 10/0.501 ≈ 20m (too far)
        // Use raw depth 5.0 → meters ≈ 10/5.001 ≈ 2m
        for i in 0..<5 {
            obstacleDistance[i] = 5.0
        }
        for i in 8..<columns {
            obstacleDistance[i] = 5.0
        }

        let scene = makeScene(
            columns: columns,
            traversability: traversability,
            obstacleDistance: obstacleDistance
        )

        let result = planner.update(
            scene: scene,
            userPosition: simd_float3(0, 0, 0),
            userHeading: 0,
            deltaTime: 1.0 / 60.0,
            grid: &grid
        )

        XCTAssertEqual(result.suggestedHeading, 0, accuracy: 0.5,
                        "Corridor heading should be roughly straight")
        XCTAssertFalse(result.isPathBlocked)
    }

    // MARK: - Test 4: Discontinuity ahead

    func testDiscontinuityAhead_detected() {
        let planner = NavigationPlanner()
        var grid = OccupancyGrid(cellSize: 0.1, gridSize: 200)

        let columns = 12
        let centerCol = columns / 2

        let disc = Discontinuity(
            column: centerCol,
            bearing: 0.0,  // straight ahead
            relativeDepth: 5.0,  // raw depth → meters ≈ 10/5.001 ≈ 2m
            magnitude: 0.5,
            direction: .dropaway
        )

        let scene = makeScene(
            columns: columns,
            discontinuities: [disc]
        )

        let result = planner.update(
            scene: scene,
            userPosition: simd_float3(0, 0, 0),
            userHeading: 0,
            deltaTime: 1.0 / 60.0,
            grid: &grid
        )

        XCTAssertNotNil(result.discontinuityAhead,
                         "Should detect discontinuity ahead in forward arc")
        XCTAssertEqual(result.discontinuityAhead?.magnitude, 0.5, accuracy: 0.01)
    }

    // MARK: - Test 5: Completely blocked

    func testCompletelyBlocked() {
        let planner = NavigationPlanner()
        planner.safetyMargin = 0.5
        var grid = OccupancyGrid(cellSize: 0.1, gridSize: 200)

        let columns = 12
        // All columns have obstacles very close: raw depth high → meters small
        // meters = 10 / (rawDepth + 0.001). We want meters < safetyMargin (0.5m)
        // So rawDepth > 10/0.5 - 0.001 = 19.999. Use rawDepth = 25 → meters ≈ 0.4m
        let obstacleDistance = Array(repeating: Float(25.0), count: columns)
        let traversability = Array(repeating: Float(0.0), count: columns)

        let scene = makeScene(
            columns: columns,
            traversability: traversability,
            obstacleDistance: obstacleDistance
        )

        let result = planner.update(
            scene: scene,
            userPosition: simd_float3(0, 0, 0),
            userHeading: 0,
            deltaTime: 1.0 / 60.0,
            grid: &grid
        )

        XCTAssertTrue(result.isPathBlocked,
                       "Should be blocked when all directions have obstacles within safety margin")
    }
}
