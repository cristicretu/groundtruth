// MockModules.swift
// Mock implementations so the app compiles and runs before real modules merge
// When real implementations are ready: swap MockVisionPipeline → RealVisionPipeline etc.
import simd
import CoreVideo

// MARK: - Mock Vision Pipeline

final class MockVisionPipeline: VisionProcessing {
    func process(frame: CVPixelBuffer) -> VisionResult {
        // Return a small dummy depth map and segmentation
        let w = 32
        let h = 24
        let depth = [Float](repeating: 3.0, count: w * h)      // 3m everywhere
        let seg = [UInt8](repeating: 0, count: w * h)           // All "unknown"
        return VisionResult(
            depthData: depth,
            depthWidth: w,
            depthHeight: h,
            segLabels: seg,
            segWidth: w,
            segHeight: h
        )
    }
}

// MARK: - Mock Scene Analyzer

final class MockSceneAnalyzer: SceneAnalyzing {
    func analyze(depthData: [Float], depthWidth: Int, depthHeight: Int,
                 segLabels: [UInt8], segWidth: Int, segHeight: Int,
                 cameraHFOV: Float) -> SceneUnderstanding {
        // Return a clear scene — no obstacles, decent ground confidence
        return SceneUnderstanding(
            obstacles: [],
            groundPlane: GroundPlane(confidence: 0.8, extent: 5.0),
            discontinuities: [],
            freeSpaceAngles: [0]    // Straight ahead is clear
        )
    }
}

// MARK: - Mock Navigation Planner

final class MockNavigationPlanner: NavigationPlanning {
    func update(scene: SceneUnderstanding, userPosition: simd_float3,
                userHeading: Float, deltaTime: Float,
                grid: inout OccupancyGrid) -> NavigationOutput {
        // Pass through: suggest current heading, report clear path
        return NavigationOutput(
            suggestedHeading: userHeading,
            nearestObstacleDistance: scene.groundPlane.extent,
            discontinuityAhead: scene.discontinuities.first,
            isPathBlocked: false,
            groundConfidence: scene.groundPlane.confidence
        )
    }
}
