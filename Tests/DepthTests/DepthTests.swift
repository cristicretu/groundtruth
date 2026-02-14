import XCTest
@testable import Depth

final class DepthMapTests: XCTestCase {

    // 3x3 grid with known values
    private func makeTestMap() -> DepthMap {
        // Row-major 3x3:
        //  1  2  3
        //  4  5  6
        //  7  8  9
        let data: [Float] = [1, 2, 3, 4, 5, 6, 7, 8, 9]
        return DepthMap(width: 3, height: 3, data: data, timestamp: 0)
    }

    func testDepthAtPixel() {
        let map = makeTestMap()
        XCTAssertEqual(map.depth(atPixelX: 0, py: 0), 1)
        XCTAssertEqual(map.depth(atPixelX: 2, py: 2), 9)
        XCTAssertEqual(map.depth(atPixelX: 1, py: 1), 5)
    }

    func testDepthAtPixelOutOfBounds() {
        let map = makeTestMap()
        XCTAssertEqual(map.depth(atPixelX: -1, py: 0), .infinity)
        XCTAssertEqual(map.depth(atPixelX: 3, py: 0), .infinity)
        XCTAssertEqual(map.depth(atPixelX: 0, py: 3), .infinity)
    }

    func testDepthAtNormalized() {
        let map = makeTestMap()

        // Corners
        XCTAssertEqual(map.depth(atX: 0, y: 0), 1, accuracy: 0.001)
        XCTAssertEqual(map.depth(atX: 1, y: 1), 9, accuracy: 0.001)

        // Center
        XCTAssertEqual(map.depth(atX: 0.5, y: 0.5), 5, accuracy: 0.001)

        // Midpoint of top edge: interpolation between 1 and 2
        XCTAssertEqual(map.depth(atX: 0.25, y: 0), 1.5, accuracy: 0.001)

        // Out of bounds
        XCTAssertEqual(map.depth(atX: -0.1, y: 0.5), .infinity)
        XCTAssertEqual(map.depth(atX: 0.5, y: 1.1), .infinity)
    }

    func testAverageDepth() {
        let map = makeTestMap()

        // Full image average: (1+2+3+4+5+6+7+8+9)/9 = 5
        let avg = map.averageDepth(in: CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertEqual(avg, 5, accuracy: 0.001)
    }

    func testAverageDepthWithInfinity() {
        let data: [Float] = [1, .infinity, 3, 4]
        let map = DepthMap(width: 2, height: 2, data: data, timestamp: 0)

        let avg = map.averageDepth(in: CGRect(x: 0, y: 0, width: 1, height: 1))
        // (1 + 3 + 4) / 3 = 2.666...
        XCTAssertEqual(avg, 8.0 / 3.0, accuracy: 0.001)
    }

    func testMinMaxDepth() {
        let map = makeTestMap()
        XCTAssertEqual(map.minDepth, 1)
        XCTAssertEqual(map.maxDepth, 9)
    }

    func testEstimatorWithModel() throws {
        // Integration test — skipped if no compiled model is available
        let modelPath = "DepthAnythingV2Small.mlmodelc"
        let modelURL = URL(fileURLWithPath: modelPath)
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw XCTSkip("Compiled model not found at \(modelPath). Run export_depth.py and compile first.")
        }

        let estimator = try DepthEstimator(modelURL: modelURL)

        // Create a dummy 518x518 pixel buffer
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(nil, 518, 518, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            XCTFail("Failed to create pixel buffer")
            return
        }

        let depthMap = try estimator.estimate(pixelBuffer: buffer)

        XCTAssertGreaterThan(depthMap.width, 0)
        XCTAssertGreaterThan(depthMap.height, 0)
        XCTAssertEqual(depthMap.data.count, depthMap.width * depthMap.height)
        XCTAssertGreaterThanOrEqual(depthMap.minDepth, 0)
        XCTAssertLessThanOrEqual(depthMap.maxDepth, 30.0)
    }
}
