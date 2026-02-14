// VisionPipelineTests.swift
// Tests for VisionPipeline: model loading and inference on dummy frames

import XCTest
import CoreVideo
@testable import groundtruth

final class VisionPipelineTests: XCTestCase {

    // MARK: - VisionResult

    func testVisionResultStruct() {
        let result = VisionResult(
            depthWidth: 518,
            depthHeight: 518,
            depthData: [Float](repeating: 0.5, count: 518 * 518),
            segWidth: 448,
            segHeight: 448,
            segLabels: [UInt8](repeating: 1, count: 448 * 448),
            timestamp: 123.456,
            depthInferenceMs: 30.0,
            segInferenceMs: 40.0,
            totalMs: 42.0
        )
        XCTAssertEqual(result.depthWidth, 518)
        XCTAssertEqual(result.depthHeight, 518)
        XCTAssertEqual(result.depthData.count, 518 * 518)
        XCTAssertEqual(result.segWidth, 448)
        XCTAssertEqual(result.segHeight, 448)
        XCTAssertEqual(result.segLabels.count, 448 * 448)
        XCTAssertEqual(result.timestamp, 123.456, accuracy: 0.001)
        XCTAssertEqual(result.depthInferenceMs, 30.0, accuracy: 0.001)
        XCTAssertEqual(result.segInferenceMs, 40.0, accuracy: 0.001)
        XCTAssertEqual(result.totalMs, 42.0, accuracy: 0.001)
    }

    // MARK: - Model Loading (requires compiled models in test bundle)

    func testPipelineLoads() throws {
        // Skip if models aren't available in the test bundle
        guard Bundle.main.url(forResource: "DepthAnythingV2SmallF16", withExtension: "mlmodelc") != nil
           || Bundle.main.url(forResource: "DepthAnythingV2Small", withExtension: "mlmodelc") != nil else {
            throw XCTSkip("Depth model not found in bundle. Add DepthAnythingV2SmallF16.mlmodelc to the test target.")
        }
        guard Bundle.main.url(forResource: "DETRResnet50SemanticSegmentationF16", withExtension: "mlmodelc") != nil
           || Bundle.main.url(forResource: "DETRResnet50SemanticSegmentation", withExtension: "mlmodelc") != nil else {
            throw XCTSkip("Segmentation model not found in bundle. Add DETRResnet50SemanticSegmentationF16.mlmodelc to the test target.")
        }

        let pipeline = try VisionPipeline()
        // If we get here, both models loaded successfully
        _ = pipeline
    }

    func testProcessDummyFrame() throws {
        // Skip if models aren't available
        guard Bundle.main.url(forResource: "DepthAnythingV2SmallF16", withExtension: "mlmodelc") != nil
           || Bundle.main.url(forResource: "DepthAnythingV2Small", withExtension: "mlmodelc") != nil else {
            throw XCTSkip("Depth model not found in bundle.")
        }
        guard Bundle.main.url(forResource: "DETRResnet50SemanticSegmentationF16", withExtension: "mlmodelc") != nil
           || Bundle.main.url(forResource: "DETRResnet50SemanticSegmentation", withExtension: "mlmodelc") != nil else {
            throw XCTSkip("Segmentation model not found in bundle.")
        }

        let pipeline = try VisionPipeline()

        // Create a dummy 640x480 BGRA pixel buffer
        let buffer = try createDummyPixelBuffer(width: 640, height: 480)

        let result = pipeline.process(frame: buffer)

        // Verify depth output
        XCTAssertGreaterThan(result.depthWidth, 0, "Depth width should be > 0")
        XCTAssertGreaterThan(result.depthHeight, 0, "Depth height should be > 0")
        XCTAssertEqual(result.depthData.count, result.depthWidth * result.depthHeight,
                       "Depth data count should match width * height")

        // Verify seg output
        XCTAssertGreaterThan(result.segWidth, 0, "Seg width should be > 0")
        XCTAssertGreaterThan(result.segHeight, 0, "Seg height should be > 0")
        XCTAssertEqual(result.segLabels.count, result.segWidth * result.segHeight,
                       "Seg labels count should match width * height")

        // Verify timing
        XCTAssertGreaterThan(result.depthInferenceMs, 0, "Depth inference time should be > 0")
        XCTAssertGreaterThan(result.segInferenceMs, 0, "Seg inference time should be > 0")
        XCTAssertGreaterThan(result.totalMs, 0, "Total time should be > 0")

        // Log output shapes and value ranges
        let depthMin = result.depthData.min() ?? 0
        let depthMax = result.depthData.max() ?? 0
        print("[TEST] Depth output: \(result.depthWidth)x\(result.depthHeight), range: [\(depthMin), \(depthMax)]")
        print("[TEST] Seg output: \(result.segWidth)x\(result.segHeight)")
        print("[TEST] Timing: depth=\(String(format: "%.1f", result.depthInferenceMs))ms, seg=\(String(format: "%.1f", result.segInferenceMs))ms, total=\(String(format: "%.1f", result.totalMs))ms")

        // Log seg class distribution
        var counts = [UInt8: Int]()
        for label in result.segLabels {
            counts[label, default: 0] += 1
        }
        let sorted = counts.sorted { $0.key < $1.key }
        for (classId, count) in sorted {
            print("[TEST] class \(classId): \(count) pixels")
        }
    }

    // MARK: - Helpers

    private func createDummyPixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw NSError(domain: "VisionPipelineTests", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create pixel buffer"])
        }
        return buffer
    }
}
