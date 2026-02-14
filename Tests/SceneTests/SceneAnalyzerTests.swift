import XCTest
@testable import Scene

final class SceneAnalyzerTests: XCTestCase {

    let analyzer = SceneAnalyzer()
    let hfov: Float = 2.0  // ~115° ultrawide

    // Helpers
    static let walkableID: UInt8 = 21   // road
    static let blockedID: UInt8 = 1     // wall/building

    /// Create uniform seg labels
    func makeSegLabels(width: Int, height: Int, value: UInt8) -> [UInt8] {
        [UInt8](repeating: value, count: width * height)
    }

    /// Create smooth depth gradient (top=far, bottom=near)
    func makeSmoothDepth(width: Int, height: Int, near: Float = 0.5, far: Float = 5.0) -> [Float] {
        var data = [Float](repeating: 0, count: width * height)
        for row in 0..<height {
            let t = Float(row) / Float(height - 1)
            // Row 0 = top of image = far, row H-1 = bottom = near
            let d = near + (far - near) * (1.0 - t)
            for x in 0..<width {
                data[row * width + x] = d
            }
        }
        return data
    }

    // MARK: - Test 1: Clear path

    func testClearPath() {
        let w = 72, h = 72
        let seg = makeSegLabels(width: w, height: h, value: Self.walkableID)
        let depth = makeSmoothDepth(width: w, height: h)

        let result = analyzer.analyze(
            depthData: depth, depthWidth: w, depthHeight: h,
            segLabels: seg, segWidth: w, segHeight: h,
            cameraHFOV: hfov
        )

        // All traversability should be ~1.0
        for col in 0..<result.columns {
            XCTAssertEqual(result.traversability[col], 1.0, accuracy: 0.01,
                           "Column \(col) should be fully traversable")
        }

        // No discontinuities (smooth gradient only)
        XCTAssertTrue(result.discontinuities.isEmpty, "Should have no discontinuities on smooth ground")

        // High ground ratio
        XCTAssertGreaterThan(result.groundPlaneRatio, 0.9)

        // All obstacle distances should be infinity
        for col in 0..<result.columns {
            XCTAssertEqual(result.obstacleDistance[col], Float.infinity,
                           "Column \(col) should have no obstacles")
        }
    }

    // MARK: - Test 2: Wall on left

    func testWallOnLeft() {
        let w = 72, h = 72
        var seg = [UInt8](repeating: 0, count: w * h)

        for row in 0..<h {
            for x in 0..<w {
                seg[row * w + x] = x < w / 2 ? Self.blockedID : Self.walkableID
            }
        }

        let depth = makeSmoothDepth(width: w, height: h)

        let result = analyzer.analyze(
            depthData: depth, depthWidth: w, depthHeight: h,
            segLabels: seg, segWidth: w, segHeight: h,
            cameraHFOV: hfov
        )

        let midCol = result.columns / 2

        // Left columns should be ~0
        for col in 0..<midCol - 1 {
            XCTAssertLessThan(result.traversability[col], 0.1,
                              "Left column \(col) should be blocked")
        }

        // Right columns should be ~1
        for col in (midCol + 1)..<result.columns {
            XCTAssertGreaterThan(result.traversability[col], 0.9,
                                 "Right column \(col) should be traversable")
        }
    }

    // MARK: - Test 3: Discontinuity detection

    func testDiscontinuityDetection() {
        let w = 72, h = 72
        let seg = makeSegLabels(width: w, height: h, value: Self.walkableID)

        // Smooth depth with a sharp drop in the middle of the ground region
        var depth = makeSmoothDepth(width: w, height: h, near: 1.0, far: 5.0)

        // Insert a sharp depth jump at ~70% from top (within bottom 40% ground region)
        let jumpRow = Int(Float(h) * 0.7)
        for row in jumpRow..<min(jumpRow + 3, h) {
            for x in 0..<w {
                depth[row * w + x] += 3.0  // Sudden large increase = drop-away
            }
        }

        let a = SceneAnalyzer()
        a.discontinuityThreshold = 0.05  // Sensitive

        let result = a.analyze(
            depthData: depth, depthWidth: w, depthHeight: h,
            segLabels: seg, segWidth: w, segHeight: h,
            cameraHFOV: hfov
        )

        XCTAssertFalse(result.discontinuities.isEmpty, "Should detect discontinuity")

        // All detected discontinuities should be dropaway (depth increased)
        for disc in result.discontinuities {
            XCTAssertEqual(disc.direction, .dropaway, "Should be a drop-away discontinuity")
            XCTAssertGreaterThan(disc.magnitude, 0.3, "Magnitude should be significant")
        }
    }

    // MARK: - Test 4: Obstacle in center

    func testObstacleInCenter() {
        let w = 72, h = 72
        var seg = makeSegLabels(width: w, height: h, value: Self.walkableID)

        // Place a non-walkable cluster in center, bottom half
        let obstacleMinX = w / 3
        let obstacleMaxX = 2 * w / 3
        let obstacleMinY = h / 2
        let obstacleMaxY = 3 * h / 4

        for row in obstacleMinY..<obstacleMaxY {
            for x in obstacleMinX..<obstacleMaxX {
                seg[row * w + x] = Self.blockedID
            }
        }

        let depth = makeSmoothDepth(width: w, height: h)

        let result = analyzer.analyze(
            depthData: depth, depthWidth: w, depthHeight: h,
            segLabels: seg, segWidth: w, segHeight: h,
            cameraHFOV: hfov
        )

        // Center columns should have finite obstacle distance
        let centerCol = result.columns / 2
        XCTAssertTrue(result.obstacleDistance[centerCol].isFinite,
                       "Center should have finite obstacle distance")

        // Far left and far right should be clear
        XCTAssertEqual(result.obstacleDistance[0], Float.infinity,
                        "Far left should have no obstacle")
        XCTAssertEqual(result.obstacleDistance[result.columns - 1], Float.infinity,
                        "Far right should have no obstacle")
    }

    // MARK: - Test 5: No walkable ground

    func testNoWalkableGround() {
        let w = 72, h = 72
        let seg = makeSegLabels(width: w, height: h, value: Self.blockedID)
        let depth = makeSmoothDepth(width: w, height: h)

        let result = analyzer.analyze(
            depthData: depth, depthWidth: w, depthHeight: h,
            segLabels: seg, segWidth: w, segHeight: h,
            cameraHFOV: hfov
        )

        // All traversability ~0
        for col in 0..<result.columns {
            XCTAssertLessThan(result.traversability[col], 0.01,
                              "Column \(col) should not be traversable")
        }

        // Ground plane ratio ~0
        XCTAssertLessThan(result.groundPlaneRatio, 0.01)
    }
}
