import Foundation

struct VisionResult {
    let depthWidth: Int
    let depthHeight: Int
    let depthData: [Float]          // Row-major, raw model output values
    let segWidth: Int
    let segHeight: Int
    let segLabels: [UInt8]          // Row-major, COCO panoptic class IDs per pixel
    let timestamp: TimeInterval
    let depthInferenceMs: Double
    let segInferenceMs: Double
    let totalMs: Double
}
