import CoreML
import Vision
import CoreVideo
import QuartzCore

enum VisionPipelineError: Error {
    case modelNotFound(String)
    case depthNoResults
    case depthUnexpectedShape([Int])
    case segNoResults
    case segUnexpectedShape([Int])
}

final class VisionPipeline {
    private let depthModel: VNCoreMLModel
    private let segModel: VNCoreMLModel

    private let depthQueue = DispatchQueue(label: "vision.depth", qos: .userInteractive)
    private let segQueue = DispatchQueue(label: "vision.seg", qos: .userInteractive)

    private var isFirstFrame = true

    init() throws {
        // Load depth model
        guard let depthURL = Bundle.main.url(forResource: "DepthAnythingV2SmallF16", withExtension: "mlmodelc")
           ?? Bundle.main.url(forResource: "DepthAnythingV2Small", withExtension: "mlmodelc") else {
            throw VisionPipelineError.modelNotFound("DepthAnythingV2SmallF16.mlmodelc")
        }
        let depthConfig = MLModelConfiguration()
        depthConfig.computeUnits = .all
        let depthML = try MLModel(contentsOf: depthURL, configuration: depthConfig)
        self.depthModel = try VNCoreMLModel(for: depthML)

        // Load segmentation model
        guard let segURL = Bundle.main.url(forResource: "DETRResnet50SemanticSegmentationF16", withExtension: "mlmodelc")
           ?? Bundle.main.url(forResource: "DETRResnet50SemanticSegmentation", withExtension: "mlmodelc") else {
            throw VisionPipelineError.modelNotFound("DETRResnet50SemanticSegmentationF16.mlmodelc")
        }
        let segConfig = MLModelConfiguration()
        segConfig.computeUnits = .all
        let segML = try MLModel(contentsOf: segURL, configuration: segConfig)
        self.segModel = try VNCoreMLModel(for: segML)

        print("[VISION] Both models loaded successfully")
    }

    func process(frame: CVPixelBuffer) -> VisionResult {
        let totalStart = CACurrentMediaTime()
        let group = DispatchGroup()

        // Depth results
        var depthWidth = 0
        var depthHeight = 0
        var depthData = [Float]()
        var depthMs: Double = 0

        // Seg results
        var segWidth = 0
        var segHeight = 0
        var segLabels = [UInt8]()
        var segMs: Double = 0

        // Run depth inference
        group.enter()
        depthQueue.async {
            defer { group.leave() }
            let start = CACurrentMediaTime()

            let handler = VNImageRequestHandler(cvPixelBuffer: frame, orientation: .up)
            let request = VNCoreMLRequest(model: self.depthModel)
            request.imageCropAndScaleOption = .scaleFill

            do {
                try handler.perform([request])
            } catch {
                print("[VISION] depth inference failed: \(error)")
                return
            }

            guard let result = request.results?.first as? VNCoreMLFeatureValueObservation,
                  let multiArray = result.featureValue.multiArrayValue else {
                print("[VISION] depth: no results")
                return
            }

            let shape = multiArray.shape.map { $0.intValue }
            let h: Int
            let w: Int
            if shape.count == 3 {
                h = shape[1]; w = shape[2]
            } else if shape.count == 2 {
                h = shape[0]; w = shape[1]
            } else {
                print("[VISION] depth: unexpected shape \(shape)")
                return
            }

            let count = h * w
            var data = [Float](repeating: 0, count: count)
            for i in 0..<count {
                data[i] = multiArray[i].floatValue
            }

            depthWidth = w
            depthHeight = h
            depthData = data
            depthMs = (CACurrentMediaTime() - start) * 1000
        }

        // Run segmentation inference
        group.enter()
        segQueue.async {
            defer { group.leave() }
            let start = CACurrentMediaTime()

            let handler = VNImageRequestHandler(cvPixelBuffer: frame, orientation: .up)
            let request = VNCoreMLRequest(model: self.segModel)
            request.imageCropAndScaleOption = .scaleFill

            do {
                try handler.perform([request])
            } catch {
                print("[VISION] seg inference failed: \(error)")
                return
            }

            // DETR outputs semanticPredictions as Int32 per-pixel class IDs
            // Find the observation with the segmentation data
            guard let results = request.results as? [VNCoreMLFeatureValueObservation] else {
                print("[VISION] seg: no results")
                return
            }

            // Try to find semanticPredictions output, fall back to first multiarray
            var multiArray: MLMultiArray?
            for obs in results {
                if obs.featureName == "semanticPredictions" {
                    multiArray = obs.featureValue.multiArrayValue
                    break
                }
            }
            if multiArray == nil {
                multiArray = results.first?.featureValue.multiArrayValue
            }

            guard let array = multiArray else {
                print("[VISION] seg: no multiarray found in results")
                return
            }

            let shape = array.shape.map { $0.intValue }
            let h: Int
            let w: Int
            if shape.count == 3 {
                h = shape[1]; w = shape[2]
            } else if shape.count == 2 {
                h = shape[0]; w = shape[1]
            } else {
                print("[VISION] seg: unexpected shape \(shape)")
                return
            }

            let count = h * w
            var labels = [UInt8](repeating: 0, count: count)
            for i in 0..<count {
                let val = array[i].intValue
                labels[i] = UInt8(clamping: val)
            }

            segWidth = w
            segHeight = h
            segLabels = labels
            segMs = (CACurrentMediaTime() - start) * 1000
        }

        group.wait()

        let totalMs = (CACurrentMediaTime() - totalStart) * 1000

        // Console logging
        let depthMin = depthData.min() ?? 0
        let depthMax = depthData.max() ?? 0
        print(String(format: "[VISION] depth: %.1fms, seg: %.1fms, total: %.1fms, depth range: [%.4f, %.4f]",
                      depthMs, segMs, totalMs, depthMin, depthMax))

        // Print class distribution on first frame
        if isFirstFrame && !segLabels.isEmpty {
            isFirstFrame = false
            var counts = [UInt8: Int]()
            for label in segLabels {
                counts[label, default: 0] += 1
            }
            let sorted = counts.sorted { $0.key < $1.key }
            let parts = sorted.map { "class \($0.key): \($0.value) pixels" }
            print("[SEG] " + parts.joined(separator: ", "))
        }

        return VisionResult(
            depthWidth: depthWidth,
            depthHeight: depthHeight,
            depthData: depthData,
            segWidth: segWidth,
            segHeight: segHeight,
            segLabels: segLabels,
            timestamp: CACurrentMediaTime(),
            depthInferenceMs: depthMs,
            segInferenceMs: segMs,
            totalMs: totalMs
        )
    }
}
