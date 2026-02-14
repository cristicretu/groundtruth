// Config.swift
// Single source of truth for all tunable parameters
// Change these HERE, not scattered across 6 files

import Foundation

// MARK: - Grid Configuration

enum GridConfig {
    static let cellSize: Float = 0.1        // 10cm cells
    static let gridSize: Int = 200          // 200x200 = 20m x 20m coverage
    static let maxDistance: Float = 10.0    // Max range to process
    
    // Derived
    static var gridExtent: Float { Float(gridSize) * cellSize }  // 20m
    static var halfGrid: Float { Float(gridSize) / 2.0 }
}

// MARK: - Elevation Thresholds

enum ElevationConfig {
    static let stepMin: Float = 0.05        // 5cm minimum to be a step
    static let stepMax: Float = 0.20        // 20cm max for step (above = curb)
    static let curbMin: Float = 0.20        // 20cm minimum for curb
    static let dropoff: Float = 0.30        // 30cm = dangerous drop
    static let rampMaxSlope: Float = 0.15   // ~8.5° max slope for ramp
    static let stairStepSize: Float = 0.18  // ~18cm typical stair step
    static let stairTolerance: Float = 0.03 // ±3cm for stair detection
    
    // Obstacle detection
    static let obstacleHeight: Float = 0.25 // Height above floor to be obstacle
    static let floorTolerance: Float = 0.20 // Height from floor to count as floor sample
}

// MARK: - Temporal Filtering

enum TemporalConfig {
    // Confidence decay per frame - stale cells fade out
    // Mesh updates are async (~5Hz), frame rate is ~60Hz
    // 0.995 decay = ~50% confidence after ~2.3s of no observations at 60Hz
    // This is slow enough that cells stay valid between mesh updates
    static let confidenceDecay: Float = 0.995
    
    // Minimum confidence to consider cell valid
    static let minConfidence: UInt8 = 20
    
    // Confidence boost per observation - high enough to cross threshold on first observation
    static let observationBoost: UInt8 = 30
    
    // Confidence cap
    static let maxConfidence: UInt8 = 255
}

// MARK: - Streaming

enum StreamConfig {
    static let port: UInt16 = 8765
    static let sendEveryNFrames: Int = 3    // ~20fps streaming at 60fps input
    static let maxElevationChanges: Int = 10
}

// MARK: - Audio Feedback

enum AudioConfig {
    // Beep intervals by distance (seconds)
    static let beepIntervalDanger: Double = 0.12   // < 0.5m
    static let beepIntervalClose: Double = 0.2     // < 1.0m
    static let beepIntervalCaution: Double = 0.35  // < 2.0m
    static let beepIntervalFar: Double = 0.5       // < 3.0m
    static let beepIntervalDistant: Double = 0.8   // < 5.0m
    
    // Elevation warning interval
    static let elevationWarningInterval: Double = 0.5
}

// MARK: - Detection (YOLO)

enum DetectionConfig {
    static let minConfidence: Float = 0.4
    static let cameraHFOV: Float = 2.094     // ~120° ultrawide
    static let inferenceInterval: Int = 3     // Every 3rd frame (~20Hz)
}

// MARK: - Processing

enum ProcessingConfig {
    // Heading smoothing - 0.2 = ~5 frame smoothing
    // Reduces BEV jitter from ARKit pose noise
    static let headingSmoothingAlpha: Float = 0.2
    
    // Floor detection - samples needed for median
    static let minFloorSamples: Int = 10
    
    // Cell validity - minimum hits to trust
    static let minHitCount: UInt16 = 3
    
    // Merge threshold for elevation warnings (meters)
    static let elevationMergeThreshold: Float = 0.5
}
