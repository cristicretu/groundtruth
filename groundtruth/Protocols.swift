// Protocols.swift
// Pipeline protocols and data types for camera-only navigation
// Real implementations are built in other worktrees — swap mocks for real classes when ready
import simd
import CoreVideo

// MARK: - Pipeline Data Types

struct VisionResult {
    var depthData: [Float]
    var depthWidth: Int
    var depthHeight: Int
    var segLabels: [UInt8]
    var segWidth: Int
    var segHeight: Int
}

struct SceneUnderstanding {
    var obstacles: [ObstacleRegion] = []
    var groundPlane: GroundPlane = GroundPlane()
    var discontinuities: [Discontinuity] = []
    var freeSpaceAngles: [Float] = []   // Bearings with clear path
}

struct ObstacleRegion {
    var bearing: Float      // Angle from center
    var distance: Float     // Meters
    var width: Float        // Angular width radians
    var height: Float       // Estimated height meters
}

struct GroundPlane {
    var confidence: Float = 0.5
    var extent: Float = 5.0
}

struct Discontinuity {
    var distance: Float = 0     // Meters ahead
    var magnitude: Float = 0    // Absolute height change meters
}

struct NavigationOutput {
    var suggestedHeading: Float = 0
    var nearestObstacleDistance: Float = .infinity
    var discontinuityAhead: Discontinuity? = nil
    var isPathBlocked: Bool = false
    var groundConfidence: Float = 1.0
}

// MARK: - Pipeline Protocols

protocol VisionProcessing {
    func process(frame: CVPixelBuffer) -> VisionResult
}

protocol SceneAnalyzing {
    func analyze(depthData: [Float], depthWidth: Int, depthHeight: Int,
                 segLabels: [UInt8], segWidth: Int, segHeight: Int,
                 cameraHFOV: Float) -> SceneUnderstanding
}

protocol NavigationPlanning {
    func update(scene: SceneUnderstanding, userPosition: simd_float3,
                userHeading: Float, deltaTime: Float,
                grid: inout OccupancyGrid) -> NavigationOutput
}
