// Depth.swift
// Pure functions for depth processing - no state, no side effects
import ARKit
import simd

struct Depth {
    
    // Extract world-space points from ARFrame depth data
    // Returns array of (position, confidence) tuples
    static func extractPoints(
        from frame: ARFrame,
        downsample: Int = 4,
        minConfidence: Int = 1,  // 0=low, 1=medium, 2=high
        maxDepth: Float = 5.0
    ) -> [(position: simd_float3, confidence: Int)] {
        
        // prefer smoothed depth
        guard let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth else {
            return []
        }
        
        let depthMap = depthData.depthMap
        let confidenceMap = depthData.confidenceMap
        
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let depthPtr = CVPixelBufferGetBaseAddress(depthMap)!
            .assumingMemoryBound(to: Float32.self)
        
        // confidence map (optional but usually present)
        var confPtr: UnsafeMutablePointer<UInt8>? = nil
        if let conf = confidenceMap {
            CVPixelBufferLockBaseAddress(conf, .readOnly)
            confPtr = CVPixelBufferGetBaseAddress(conf)!
                .assumingMemoryBound(to: UInt8.self)
        }
        defer {
            if let conf = confidenceMap {
                CVPixelBufferUnlockBaseAddress(conf, .readOnly)
            }
        }
        
        // camera intrinsics for back-projection
        let intrinsics = frame.camera.intrinsics
        let fx = intrinsics[0][0]
        let fy = intrinsics[1][1]
        let cx = intrinsics[2][0]
        let cy = intrinsics[2][1]
        
        let transform = frame.camera.transform
        
        // pre-allocate
        let capacity = (width / downsample) * (height / downsample)
        var points: [(position: simd_float3, confidence: Int)] = []
        points.reserveCapacity(capacity)
        
        for y in stride(from: 0, to: height, by: downsample) {
            for x in stride(from: 0, to: width, by: downsample) {
                let idx = y * width + x
                let depth = depthPtr[idx]
                
                // filter invalid depths
                guard depth > 0.1 && depth < maxDepth else { continue }
                
                // filter low confidence
                let confidence: Int
                if let ptr = confPtr {
                    confidence = Int(ptr[idx])
                    guard confidence >= minConfidence else { continue }
                } else {
                    confidence = 2
                }
                
                // back-project to camera space
                let xCam = (Float(x) - cx) * depth / fx
                let yCam = (Float(y) - cy) * depth / fy
                
                // camera space: x right, y down, z forward
                // we want: x right, y up, z backward (ARKit world convention)
                let camPoint = simd_float4(xCam, -yCam, -depth, 1.0)
                
                // transform to world space
                let worldPoint = transform * camPoint
                
                points.append((
                    position: simd_float3(worldPoint.x, worldPoint.y, worldPoint.z),
                    confidence: confidence
                ))
            }
        }
        
        return points
    }
    
    // Get nearest obstacle distance in center region (quick check)
    static func nearestInCenter(from frame: ARFrame, regionSize: Int = 50) -> Float? {
        guard let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth else {
            return nil
        }
        
        let depthMap = depthData.depthMap
        
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let ptr = CVPixelBufferGetBaseAddress(depthMap)!
            .assumingMemoryBound(to: Float32.self)
        
        let cx = width / 2
        let cy = height / 2
        
        var minDepth: Float = .infinity
        
        for y in max(0, cy - regionSize)..<min(height, cy + regionSize) {
            for x in max(0, cx - regionSize)..<min(width, cx + regionSize) {
                let depth = ptr[y * width + x]
                if depth > 0.2 && depth < minDepth {
                    minDepth = depth
                }
            }
        }
        
        return minDepth == .infinity ? nil : minDepth
    }
}
