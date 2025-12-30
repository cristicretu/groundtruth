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
        
        config.planeDetection = []
        
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
            print("[Sensors] FPS: \(_fps), hasDepth: \(frame.sceneDepth != nil)")
        }
        
        // fire callback
        onFrame?(frame)
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
