// Detection.swift
// YOLO object detection types for camera-based hazard identification

import CoreGraphics

// MARK: - Detected Object Type

enum DetectedObjectType: Int, CaseIterable {
    case person = 0
    case bicycle = 1
    case car = 2
    case motorcycle = 3
    case bus = 5
    case truck = 7
    case trafficLight = 9
    case stopSign = 11
    case dog = 16

    init?(cocoClassId: Int) {
        self.init(rawValue: cocoClassId)
    }

    init?(cocoName: String) {
        switch cocoName {
        case "person": self = .person
        case "bicycle": self = .bicycle
        case "car": self = .car
        case "motorcycle": self = .motorcycle
        case "bus": self = .bus
        case "truck": self = .truck
        case "traffic light": self = .trafficLight
        case "stop sign": self = .stopSign
        case "dog": self = .dog
        default: return nil
        }
    }

    var threatLevel: ThreatLevel {
        switch self {
        case .car, .bus, .truck, .motorcycle, .bicycle: return .high
        case .person: return .medium
        case .dog: return .low
        case .trafficLight, .stopSign: return .info
        }
    }

    var label: String {
        switch self {
        case .person: return "person"
        case .bicycle: return "bicycle"
        case .car: return "car"
        case .motorcycle: return "motorcycle"
        case .bus: return "bus"
        case .truck: return "truck"
        case .trafficLight: return "traffic light"
        case .stopSign: return "stop sign"
        case .dog: return "dog"
        }
    }
}

// MARK: - Threat Level

enum ThreatLevel: Int, Comparable {
    case info = 0
    case low = 1
    case medium = 2
    case high = 3

    static func < (lhs: ThreatLevel, rhs: ThreatLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Detection

struct Detection {
    let objectType: DetectedObjectType
    let confidence: Float
    let boundingBox: CGRect       // Normalized [0,1] coordinates
    let bearing: Float            // Radians from center (positive = left, negative = right)
}
