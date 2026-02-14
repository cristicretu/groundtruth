// ObjectDetector.swift
// CoreML/Vision YOLO inference for camera-based object detection

import CoreML
import Vision
import CoreVideo
import QuartzCore

final class ObjectDetector {
    private var model: VNCoreMLModel?
    private var isLoaded = false
    private(set) var inferenceTimeMs: Double = 0

    // MARK: - Model Loading

    private func loadModel() {
        guard !isLoaded else { return }
        isLoaded = true

        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            guard let modelURL = Bundle.main.url(forResource: "yolo11n", withExtension: "mlmodelc") else {
                print("[Detector] yolo11n.mlmodelc not found in bundle")
                return
            }
            let mlModel = try MLModel(contentsOf: modelURL, configuration: config)
            model = try VNCoreMLModel(for: mlModel)
            print("[Detector] model loaded successfully")
        } catch {
            print("[Detector] failed to load model: \(error)")
        }
    }

    // MARK: - Synchronous Detection

    func detect(pixelBuffer: CVPixelBuffer) -> [Detection] {
        loadModel()
        guard let model else { return [] }

        let start = CACurrentMediaTime()

        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFill

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        do {
            try handler.perform([request])
        } catch {
            print("[Detector] inference failed: \(error)")
            return []
        }

        inferenceTimeMs = (CACurrentMediaTime() - start) * 1000

        guard let results = request.results as? [VNRecognizedObjectObservation] else {
            return []
        }

        return parseResults(results)
    }

    // MARK: - Result Parsing

    private func parseResults(_ observations: [VNRecognizedObjectObservation]) -> [Detection] {
        var detections: [Detection] = []

        for obs in observations {
            guard let topLabel = obs.labels.first,
                  topLabel.confidence >= DetectionConfig.minConfidence,
                  let objectType = DetectedObjectType(cocoName: topLabel.identifier) else {
                continue
            }

            let bbox = obs.boundingBox
            let bearing = (0.5 - Float(bbox.midX)) * DetectionConfig.cameraHFOV

            detections.append(Detection(
                objectType: objectType,
                confidence: topLabel.confidence,
                boundingBox: bbox,
                bearing: bearing
            ))
        }

        // Sort by threat level desc, then confidence desc
        detections.sort { a, b in
            if a.objectType.threatLevel != b.objectType.threatLevel {
                return a.objectType.threatLevel > b.objectType.threatLevel
            }
            return a.confidence > b.confidence
        }

        return detections
    }
}
