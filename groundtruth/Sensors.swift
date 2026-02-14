// Sensors.swift
// Clean ARSession capture - callback-based, camera + pose ONLY
import ARKit

final class Sensors: NSObject {
    private let session = ARSession()
    private let queue = DispatchQueue(label: "sensors", qos: .userInteractive)

    // callback on every frame - called on sensor queue, not main
    var onFrame: ((ARFrame) -> Void)?

    // error callback
    var onError: ((Error) -> Void)?

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
        session.delegateQueue = queue
        print("[Sensors] initialized")
    }

    func start() -> Bool {
        print("[Sensors] start() called")

        let config = ARWorldTrackingConfiguration()
        // Camera + pose only — no mesh, no scene reconstruction
        config.isAutoFocusEnabled = true

        print("[Sensors] running session (camera-only)...")
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

            let currentFps = _fpsInternal
            Task { @MainActor in
                self.fps = currentFps
            }
            print("[Sensors] FPS: \(currentFps)")
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
