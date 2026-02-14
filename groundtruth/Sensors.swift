// Sensors.swift
// Clean ARSession capture - callback-based, no Combine overhead
import ARKit

final class Sensors: NSObject {
    private let session = ARSession()
    private let queue = DispatchQueue(label: "sensors", qos: .userInteractive)
    
    // callback on every frame - called on sensor queue, not main
    var onFrame: ((ARFrame) -> Void)?

    // error callback
    var onError: ((Error) -> Void)?
    
    // current mesh anchors - protected by lock for thread safety
    private var meshAnchors: [ARMeshAnchor] = []
    private let meshLock = NSLock()

    // FPS tracking - only for UI display, updated on main thread
    private var _fpsInternal: Int = 0
    private var _frameCountInternal: Int = 0
    private var lastFPSTime = CACurrentMediaTime()
    
    // Thread-safe FPS accessor - published on main thread
    @MainActor private(set) var fps: Int = 0
    @MainActor private(set) var frameCount: Int = 0
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
        
        // Enable scene reconstruction with classification
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
            print("[Sensors] Scene Reconstruction WITH CLASSIFICATION enabled")
        } else if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
            print("[Sensors] Scene Reconstruction (mesh only, no classification)")
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
        _fpsInternal = 0
        _frameCountInternal = 0
        Task { @MainActor in
            self.fps = 0
            self.frameCount = 0
        }
        meshLock.lock()
        meshAnchors.removeAll()
        meshLock.unlock()
    }

    // Get current mesh anchors - thread safe copy
    func getMeshAnchors() -> [ARMeshAnchor] {
        meshLock.lock()
        let copy = meshAnchors
        meshLock.unlock()
        return copy
    }
}

extension Sensors: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        _frameCountInternal += 1
        let now = CACurrentMediaTime()
        if now - lastFPSTime >= 1.0 {
            _fpsInternal = _frameCountInternal
            _frameCountInternal = 0
            lastFPSTime = now
            
            // Update main-thread accessible values
            let currentFps = _fpsInternal
            let currentFrameCount = _frameCountInternal
            let meshCount = meshAnchors.count
            let hasDepth = frame.sceneDepth != nil
            Task { @MainActor in
                self.fps = currentFps
                self.frameCount = currentFrameCount
            }
            print("[Sensors] FPS: \(currentFps), hasDepth: \(hasDepth), meshes: \(meshCount)")
        }
        
        // fire callback
        onFrame?(frame)
    }
    
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        let newMeshes = anchors.compactMap { $0 as? ARMeshAnchor }
        if !newMeshes.isEmpty {
            meshLock.lock()
            meshAnchors.append(contentsOf: newMeshes)
            let total = meshAnchors.count
            meshLock.unlock()
            print("[Sensors] Added \(newMeshes.count) mesh anchors, total: \(total)")
        }
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        let updatedMeshes = anchors.compactMap { $0 as? ARMeshAnchor }
        guard !updatedMeshes.isEmpty else { return }

        meshLock.lock()
        for meshAnchor in updatedMeshes {
            if let index = meshAnchors.firstIndex(where: { $0.identifier == meshAnchor.identifier }) {
                meshAnchors[index] = meshAnchor
            }
        }
        meshLock.unlock()
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        let removedIDs = Set(anchors.compactMap { ($0 as? ARMeshAnchor)?.identifier })
        guard !removedIDs.isEmpty else { return }

        meshLock.lock()
        meshAnchors.removeAll { removedIDs.contains($0.identifier) }
        let remaining = meshAnchors.count
        meshLock.unlock()
        print("[Sensors] Removed mesh anchors, remaining: \(remaining)")
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
