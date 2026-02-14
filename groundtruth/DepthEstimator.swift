import CoreML
import Vision
import CoreVideo
import QuartzCore

public final class DepthEstimator {
    private let vnModel: VNCoreMLModel

    /// Scale factor converting relative depth to meters: `meters = depthScale / (relativeDepth + epsilon)`
    public var depthScale: Float = 10.0

    /// Maximum reliable depth in meters. Values beyond this are clamped.
    public var maxReliableDepth: Float = 30.0

    public init(modelURL: URL) throws {
        let config = MLModelConfiguration()
        config.computeUnits = .all
        let mlModel = try MLModel(contentsOf: modelURL, configuration: config)
        self.vnModel = try VNCoreMLModel(for: mlModel)
    }

    public func estimate(pixelBuffer: CVPixelBuffer) throws -> DepthMap {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        let request = VNCoreMLRequest(model: vnModel)
        request.imageCropAndScaleOption = .scaleFill

        try handler.perform([request])

        guard let result = request.results?.first as? VNCoreMLFeatureValueObservation,
              let multiArray = result.featureValue.multiArrayValue else {
            throw DepthEstimatorError.noResults
        }

        let shape = multiArray.shape.map { $0.intValue }
        // Output shape is typically [1, height, width] or [height, width]
        let h: Int
        let w: Int
        if shape.count == 3 {
            h = shape[1]
            w = shape[2]
        } else if shape.count == 2 {
            h = shape[0]
            w = shape[1]
        } else {
            throw DepthEstimatorError.unexpectedShape(shape)
        }

        let count = h * w
        let epsilon: Float = 1e-6
        let scale = depthScale
        let maxDepth = maxReliableDepth

        var depthData = [Float](repeating: 0, count: count)

        for i in 0..<count {
            // Do not bind raw pointer as Float blindly: model outputs can be Float16/Double.
            let relative = multiArray[i].floatValue
            let meters = scale / (relative + epsilon)
            depthData[i] = min(max(meters, 0), maxDepth)
        }

        return DepthMap(
            width: w,
            height: h,
            data: depthData,
            timestamp: CACurrentMediaTime()
        )
    }

    public func estimateAsync(pixelBuffer: CVPixelBuffer) async throws -> DepthMap {
        try estimate(pixelBuffer: pixelBuffer)
    }
}

public enum DepthEstimatorError: Error {
    case noResults
    case unexpectedShape([Int])
}
