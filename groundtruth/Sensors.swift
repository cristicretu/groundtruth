// Sensors.swift
// Clean ARSession capture - callback-based, no Combine overhead
import ARKit

final class Sensors: NSObject {
    private let session = ARSession()
    private let queue = DispatchQueue(label: "sensors", qos: .userInteractive)
    
    // callback on every frame - called on sensor queue, not main
    var onFrame: ((ARFrame) -> Void)?
    
    // callback for mesh updates - provides actual 3D geometry
    var onMeshUpdate: (([ARMeshAnchor]) -> Void)?
    
    // error callback
    var onError: ((Error) -> Void)?
    
    // current mesh anchors
    private var meshAnchors: [ARMeshAnchor] = []
    
    // stats - use atomic for thread safety
    private var _fps: Int = 0
    private var _frameCount: Int = 0
    var fps: Int { _fps }
    var frameCount: Int { _frameCount }
    
    private var lastFPSTime = CACurrentMediaTime()
    private(set) var isRunning = false
    
    override init() {
        super.init()
        session.delegate = self
        session.delegateQueue = queue  // set queue early
        print("[Sensors] initialized")
    }
    
    func start() -> Bool {
        print("[Sensors] start() called")
        
        guard ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else {
            print("[Sensors] ERROR: sceneDepth not supported")
            return false
        }
        print("[Sensors] sceneDepth supported")
        
        let config = ARWorldTrackingConfiguration()
        config.frameSemantics = [.sceneDepth]
        
        // smoothed depth if available
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            config.frameSemantics.insert(.smoothedSceneDepth)
            print("[Sensors] smoothedSceneDepth enabled")
        }
        
        // Enable scene reconstruction for actual 3D mesh geometry!
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
            print("[Sensors] Scene Reconstruction (mesh) ENABLED - will get real 3D geometry!")
        } else {
            print("[Sensors] WARNING: Scene Reconstruction not supported")
        }
        
        config.planeDetection = [.horizontal, .vertical]
        
        print("[Sensors] running session...")
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        isRunning = true
        print("[Sensors] session started")
        
        return true
    }
    
    func stop() {
        print("[Sensors] stop() called")
        session.pause()
        isRunning = false
        _fps = 0
        _frameCount = 0
        meshAnchors.removeAll()
    }
    
    // Get current mesh anchors
    func getMeshAnchors() -> [ARMeshAnchor] {
        return meshAnchors
    }
}

extension Sensors: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        _frameCount += 1
        let now = CACurrentMediaTime()
        if now - lastFPSTime >= 1.0 {
            _fps = _frameCount
            _frameCount = 0
            lastFPSTime = now
            print("[Sensors] FPS: \(_fps), hasDepth: \(frame.sceneDepth != nil), meshes: \(meshAnchors.count)")
        }
        
        // fire callback
        onFrame?(frame)
    }
    
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        let newMeshes = anchors.compactMap { $0 as? ARMeshAnchor }
        if !newMeshes.isEmpty {
            meshAnchors.append(contentsOf: newMeshes)
            print("[Sensors] Added \(newMeshes.count) mesh anchors, total: \(meshAnchors.count)")
            onMeshUpdate?(meshAnchors)
        }
    }
    
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        var updated = false
        for anchor in anchors {
            if let meshAnchor = anchor as? ARMeshAnchor {
                // Replace existing mesh anchor with updated one
                if let index = meshAnchors.firstIndex(where: { $0.identifier == meshAnchor.identifier }) {
                    meshAnchors[index] = meshAnchor
                    updated = true
                }
            }
        }
        if updated {
            onMeshUpdate?(meshAnchors)
        }
    }
    
    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        let removedIDs = Set(anchors.compactMap { ($0 as? ARMeshAnchor)?.identifier })
        if !removedIDs.isEmpty {
            meshAnchors.removeAll { removedIDs.contains($0.identifier) }
            print("[Sensors] Removed mesh anchors, remaining: \(meshAnchors.count)")
            onMeshUpdate?(meshAnchors)
        }
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        print("[Sensors] ERROR: \(error)")
        onError?(error)
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        print("[Sensors] session interrupted")
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        print("[Sensors] interruption ended")
    }
}
