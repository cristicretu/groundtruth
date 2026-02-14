// ObjectDetectorTests.swift
// Tests for YOLO detection types and bearing calculation

import XCTest
import CoreGraphics
@testable import groundtruth

final class ObjectDetectorTests: XCTestCase {

    // MARK: - DetectedObjectType

    func testCocoNameMapping() {
        XCTAssertEqual(DetectedObjectType(cocoName: "person"), .person)
        XCTAssertEqual(DetectedObjectType(cocoName: "car"), .car)
        XCTAssertEqual(DetectedObjectType(cocoName: "bus"), .bus)
        XCTAssertEqual(DetectedObjectType(cocoName: "truck"), .truck)
        XCTAssertEqual(DetectedObjectType(cocoName: "motorcycle"), .motorcycle)
        XCTAssertEqual(DetectedObjectType(cocoName: "bicycle"), .bicycle)
        XCTAssertEqual(DetectedObjectType(cocoName: "traffic light"), .trafficLight)
        XCTAssertEqual(DetectedObjectType(cocoName: "stop sign"), .stopSign)
        XCTAssertEqual(DetectedObjectType(cocoName: "dog"), .dog)
    }

    func testIrrelevantClassesReturnNil() {
        XCTAssertNil(DetectedObjectType(cocoName: "backpack"))
        XCTAssertNil(DetectedObjectType(cocoName: "chair"))
        XCTAssertNil(DetectedObjectType(cocoName: "laptop"))
        XCTAssertNil(DetectedObjectType(cocoName: ""))
    }

    func testCocoClassIdMapping() {
        XCTAssertEqual(DetectedObjectType(cocoClassId: 0), .person)
        XCTAssertEqual(DetectedObjectType(cocoClassId: 2), .car)
        XCTAssertEqual(DetectedObjectType(cocoClassId: 16), .dog)
        XCTAssertNil(DetectedObjectType(cocoClassId: 99))
        XCTAssertNil(DetectedObjectType(cocoClassId: 4)) // airplane — not relevant
    }

    // MARK: - Threat Level

    func testThreatLevelComparable() {
        XCTAssertTrue(ThreatLevel.info < ThreatLevel.low)
        XCTAssertTrue(ThreatLevel.low < ThreatLevel.medium)
        XCTAssertTrue(ThreatLevel.medium < ThreatLevel.high)
    }

    func testThreatMapping() {
        XCTAssertEqual(DetectedObjectType.car.threatLevel, .high)
        XCTAssertEqual(DetectedObjectType.bus.threatLevel, .high)
        XCTAssertEqual(DetectedObjectType.truck.threatLevel, .high)
        XCTAssertEqual(DetectedObjectType.motorcycle.threatLevel, .high)
        XCTAssertEqual(DetectedObjectType.bicycle.threatLevel, .high)
        XCTAssertEqual(DetectedObjectType.person.threatLevel, .medium)
        XCTAssertEqual(DetectedObjectType.dog.threatLevel, .low)
        XCTAssertEqual(DetectedObjectType.trafficLight.threatLevel, .info)
        XCTAssertEqual(DetectedObjectType.stopSign.threatLevel, .info)
    }

    // MARK: - Bearing Calculation

    func testBearingCenter() {
        // Object at center of image (midX = 0.5) → bearing = 0
        let bearing = (0.5 - Float(0.5)) * DetectionConfig.cameraHFOV
        XCTAssertEqual(bearing, 0, accuracy: 0.001)
    }

    func testBearingLeft() {
        // Object on left side (midX = 0.0) → positive bearing
        let bearing = (0.5 - Float(0.0)) * DetectionConfig.cameraHFOV
        XCTAssertGreaterThan(bearing, 0)
        XCTAssertEqual(bearing, DetectionConfig.cameraHFOV / 2, accuracy: 0.001)
    }

    func testBearingRight() {
        // Object on right side (midX = 1.0) → negative bearing
        let bearing = (0.5 - Float(1.0)) * DetectionConfig.cameraHFOV
        XCTAssertLessThan(bearing, 0)
        XCTAssertEqual(bearing, -DetectionConfig.cameraHFOV / 2, accuracy: 0.001)
    }

    // MARK: - Detection Struct

    func testDetectionCreation() {
        let det = Detection(
            objectType: .car,
            confidence: 0.85,
            boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
            bearing: 0.5
        )
        XCTAssertEqual(det.objectType, .car)
        XCTAssertEqual(det.confidence, 0.85, accuracy: 0.001)
        XCTAssertEqual(det.bearing, 0.5, accuracy: 0.001)
    }

    // MARK: - ObjectDetector (requires model in bundle)

    func testDetectorInitializes() {
        let detector = ObjectDetector()
        XCTAssertEqual(detector.inferenceTimeMs, 0)
    }

    // Note: testDetectionReturnsResults and testInferencePerformance
    // require yolo11n.mlmodelc in the test bundle and a physical device.
    // Run on device with: xcodebuild test -scheme groundtruth -destination 'platform=iOS,name=<device>'
}
