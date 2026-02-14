// ElevationAnalyzer.swift
// Type definitions only — analysis logic removed (camera-only pipeline)
import simd

// Elevation change types (kept for streaming backward compat)
enum ElevationChangeType: UInt8, Codable {
    case none = 0
    case stepUp = 1
    case stepDown = 2
    case curbUp = 3
    case curbDown = 4
    case rampUp = 5
    case rampDown = 6
    case stairs = 7
    case dropoff = 8
}

// Detected elevation change (kept for audio + streaming backward compat)
struct ElevationChange: Codable {
    let type: ElevationChangeType
    let position: SIMD2<Float>
    let distance: Float
    let angle: Float
    let heightChange: Float
    let confidence: Float

    var isWarning: Bool {
        switch type {
        case .stepUp, .stepDown, .rampUp, .rampDown: return true
        default: return false
        }
    }

    var isDanger: Bool {
        switch type {
        case .curbUp, .curbDown, .dropoff: return true
        default: return false
        }
    }

    var shortDescription: String {
        switch type {
        case .stepUp: return "STEP UP"
        case .stepDown: return "STEP DOWN"
        case .curbUp: return "CURB"
        case .curbDown: return "DROP"
        case .rampUp: return "RAMP UP"
        case .rampDown: return "RAMP DOWN"
        case .stairs: return "STAIRS"
        case .dropoff: return "DANGER"
        case .none: return ""
        }
    }
}

typealias ElevationThresholds = ElevationConfig
