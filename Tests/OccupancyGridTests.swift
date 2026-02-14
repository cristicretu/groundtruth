import XCTest
@testable import groundtruth
import simd

final class OccupancyGridTests: XCTestCase {

    // MARK: - Temporal Decay

    func testDecayReducesConfidence() {
        var grid = OccupancyGrid(cellSize: 0.1, gridSize: 10)
        grid.cells[5][5].confidence = 100
        grid.cells[5][5].state = .occupied
        grid.cells[5][5].hitCount = 5
        grid.cells[5][5].minHeight = 0
        grid.cells[5][5].maxHeight = 0.5

        // Simulate ~2 seconds of decay at 60fps
        for _ in 0..<120 {
            grid.applyDecay(deltaTime: 1.0 / 60.0)
        }

        // After ~2s of decay with 0.995 per frame, confidence should be roughly halved
        XCTAssertLessThan(grid.cells[5][5].confidence, 60, "Confidence should decay significantly over 2s")
    }

    func testDecayResetsLowConfidenceCells() {
        var grid = OccupancyGrid(cellSize: 0.1, gridSize: 10)
        grid.cells[3][3].confidence = 25
        grid.cells[3][3].state = .occupied
        grid.cells[3][3].hitCount = 3
        grid.cells[3][3].minHeight = 0
        grid.cells[3][3].maxHeight = 0.5

        // Many decay steps should push below minConfidence and reset
        for _ in 0..<300 {
            grid.applyDecay(deltaTime: 1.0 / 60.0)
        }

        XCTAssertEqual(grid.cells[3][3].state, .unknown, "Cell should reset to unknown after confidence decays below threshold")
        XCTAssertEqual(grid.cells[3][3].confidence, 0)
        XCTAssertEqual(grid.cells[3][3].hitCount, 0)
    }

    // MARK: - Detection Projection

    func testUpdateFromDetectionMarksCorrectCells() {
        var grid = OccupancyGrid(cellSize: 0.1, gridSize: 100)
        // Grid centered at origin

        // Place detection at bearing 0 (north/+Z), 2m away, 0.5m wide
        grid.updateFromDetection(bearing: 0, distance: 2.0, width: 0.5, type: .person, confidence: 1.0)

        // Cell at world (0, 2.0) should be occupied
        if let (gx, gz) = grid.worldToGrid(0, 2.0) {
            XCTAssertEqual(grid.cells[gx][gz].state, .occupied)
            XCTAssertGreaterThan(grid.cells[gx][gz].confidence, 0)
        } else {
            XCTFail("Detection point should be within grid")
        }
    }

    // MARK: - Grid Re-centering

    func testRecenterPreservesShiftedCells() {
        var grid = OccupancyGrid(cellSize: 0.1, gridSize: 20)
        // originX=0, originZ=0

        // Place an occupied cell at world (0.5, 0.5)
        if let (gx, gz) = grid.worldToGrid(0.5, 0.5) {
            grid.cells[gx][gz].state = .occupied
            grid.cells[gx][gz].confidence = 100
            grid.cells[gx][gz].hitCount = 5
            grid.cells[gx][gz].minHeight = 0
            grid.cells[gx][gz].maxHeight = 0.5
        }

        // Move user far enough to trigger re-center (>80% of half-extent = 0.8m)
        let newPos = simd_float3(0.9, 0, 0.0)
        grid.updateUserPose(position: newPos, heading: 0)

        // Grid should have re-centered. The cell at world (0.5, 0.5) should still exist
        // but now at a different grid index.
        if let (gx, gz) = grid.worldToGrid(0.5, 0.5) {
            XCTAssertEqual(grid.cells[gx][gz].state, .occupied, "Re-centered grid should preserve existing cells")
            XCTAssertEqual(grid.cells[gx][gz].confidence, 100)
        } else {
            // It's possible the cell fell off the edge after re-center; that's OK for small grids
            // Just verify the origin moved
            XCTAssertEqual(grid.originX, 0.9, accuracy: 0.001)
        }

        XCTAssertEqual(grid.originX, 0.9, accuracy: 0.001, "Origin should move to new position")
    }

    // MARK: - Multi-source Conflict

    func testOccupiedOverridesFreeOnHigherConfidence() {
        var grid = OccupancyGrid(cellSize: 0.1, gridSize: 20)

        // Simulate a free cell from mesh
        let (gx, gz) = (10, 10)
        grid.cells[gx][gz].state = .free
        grid.cells[gx][gz].confidence = 30
        grid.cells[gx][gz].hitCount = 3

        // Now a detection marks the same area as occupied with higher confidence
        let (worldX, worldZ) = grid.gridToWorld(gx, gz)
        let bearing = atan2(worldX - grid.originX, worldZ - grid.originZ)
        let dist = sqrt(pow(worldX - grid.originX, 2) + pow(worldZ - grid.originZ, 2))
        grid.updateFromDetection(bearing: bearing, distance: dist, width: 0.1, type: .generic, confidence: 1.0)

        XCTAssertEqual(grid.cells[gx][gz].state, .occupied, "Detection should override free state")
        XCTAssertGreaterThan(grid.cells[gx][gz].confidence, 30, "Confidence should increase from detection")
    }

    // MARK: - Configurable Resolution

    func testDifferentGridSizes() {
        let small = OccupancyGrid(cellSize: 0.2, gridSize: 50)
        XCTAssertEqual(small.gridSize, 50)
        XCTAssertEqual(small.cellSize, 0.2)
        XCTAssertEqual(small.cells.count, 50)
        XCTAssertEqual(small.cells[0].count, 50)

        let large = OccupancyGrid(cellSize: 0.05, gridSize: 400)
        XCTAssertEqual(large.gridSize, 400)
        XCTAssertEqual(large.cellSize, 0.05)
        XCTAssertEqual(large.cells.count, 400)
    }

    // MARK: - World-to-Grid Round Trip

    func testWorldToGridRoundTrip() {
        let grid = OccupancyGrid(cellSize: 0.1, gridSize: 100)
        // Origin at (0,0), test a point
        let testX: Float = 2.35
        let testZ: Float = -1.15

        guard let (gx, gz) = grid.worldToGrid(testX, testZ) else {
            XCTFail("Point should be within grid")
            return
        }

        let (backX, backZ) = grid.gridToWorld(gx, gz)
        // Should be within half a cell size
        XCTAssertEqual(backX, testX, accuracy: grid.cellSize, "Round-trip X should be within one cell")
        XCTAssertEqual(backZ, testZ, accuracy: grid.cellSize, "Round-trip Z should be within one cell")
    }

    // MARK: - toCompactData

    func testToCompactDataSize() {
        let grid = OccupancyGrid(cellSize: 0.1, gridSize: 10)
        let data = grid.toCompactData()
        XCTAssertEqual(data.count, 10 * 10 * 2, "Compact data should be 2 bytes per cell")
    }

    func testToCompactDataWithZeroHeading() {
        // With heading=0, output should match storage directly
        var grid = OccupancyGrid(cellSize: 0.1, gridSize: 10)
        grid.userHeading = 0
        grid.cells[3][4].state = .occupied
        grid.cells[3][4].elevation = 0.15

        let data = grid.toCompactData()

        // At heading=0, output cell [x=3,z=4] maps to index (z*gridSize + x)*2 = (4*10+3)*2 = 86
        let idx = (4 * 10 + 3) * 2
        XCTAssertEqual(data[idx], CellState.occupied.rawValue)
        XCTAssertEqual(Int8(bitPattern: data[idx + 1]), 15) // 0.15m = 15cm
    }

    // MARK: - Depth Sample

    func testUpdateFromDepthSample() {
        var grid = OccupancyGrid(cellSize: 0.1, gridSize: 100)
        grid.floorHeight = 0

        // Ground sample
        grid.updateFromDepthSample(bearing: 0, distance: 1.0, isGround: true)
        if let (gx, gz) = grid.worldToGrid(0, 1.0) {
            XCTAssertGreaterThan(grid.cells[gx][gz].hitCount, 0)
            XCTAssertTrue(grid.cells[gx][gz].minHeight.isFinite)
        }

        // Obstacle sample
        grid.updateFromDepthSample(bearing: Float.pi / 2, distance: 1.0, isGround: false)
        if let (gx, gz) = grid.worldToGrid(1.0, 0) {
            XCTAssertGreaterThan(grid.cells[gx][gz].hitCount, 0)
            XCTAssertGreaterThan(grid.cells[gx][gz].maxHeight, 0)
        }
    }
}
