// App.swift
// Minimal UI - headless navigation, no camera preview
import SwiftUI
import Combine
import ARKit
import Foundation

@main
struct PathfinderApp: App {
    var body: some Scene {
        WindowGroup {
            PathfinderView()
        }
    }
}

struct PathfinderView: View {
    @StateObject private var engine = NavigationEngine()
    @State private var debugIP = "192.168.1.102"
    @State private var showDebugSettings = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                // title + debug toggle
                HStack {
                    Text("PATHFINDER")
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)

                    Spacer()

                    Button(action: { showDebugSettings.toggle() }) {
                        Image(systemName: "gear")
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal)

                // debug settings
                if showDebugSettings {
                    debugSettingsView
                }

                // status
                statusView

                Spacer()

                // debug overlay
                if engine.isRunning {
                    DebugOverlayView(engine: engine)
                }

                Spacer()

                // big start/stop button
                Button(action: {
                    print("[UI] button tapped, isRunning=\(engine.isRunning)")
                    engine.toggle()
                }) {
                    Text(engine.isRunning ? "STOP" : "START")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 80)
                        .background(engine.isRunning ? Color.red : Color.green)
                        .cornerRadius(20)
                }
                .padding(.horizontal, 32)
                .accessibilityLabel(engine.isRunning ? "Stop navigation" : "Start navigation")

                // Debug: show frame count
                Text("Frames: \(engine.fps)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding(.vertical, 48)
        }
    }

    private var debugSettingsView: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("Mac IP (e.g. 192.168.1.100)", text: $debugIP)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)

                Button("Connect") {
                    if !debugIP.isEmpty {
                        engine.connectDebug(host: debugIP)
                    }
                }
                .buttonStyle(.bordered)
            }

            HStack {
                Circle()
                    .fill(engine.isStreamConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(engine.isStreamConnected ? "Streaming to Mac" : "Not connected")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
    }

    private var statusView: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(statusColor)
                .frame(width: 60, height: 60)

            VStack(alignment: .leading) {
                Text(statusText)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)

                let dist = engine.navigationOutput.nearestObstacleDistance
                if dist < 100 {
                    Text(String(format: "%.1fm", dist))
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .foregroundColor(statusColor)
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(16)
    }

    private var statusColor: Color {
        let nav = engine.navigationOutput
        if nav.isPathBlocked { return .red }
        let dist = nav.nearestObstacleDistance
        if dist < 0.5 { return .red }
        if dist < 1.0 { return .orange }
        if dist < 2.0 { return .yellow }
        return .green
    }

    private var statusText: String {
        let nav = engine.navigationOutput
        if nav.isPathBlocked { return "BLOCKED" }
        if nav.groundConfidence < 0.3 { return "CAUTION" }
        let dist = nav.nearestObstacleDistance
        if dist > 100 { return "CLEAR" }
        if dist < 0.5 { return "STOP" }
        if dist < 1.0 { return "CLOSE" }
        if dist < 2.0 { return "CAUTION" }
        return "AHEAD"
    }
}

// The navigation engine - camera-only pipeline
final class NavigationEngine: ObservableObject {
    // Pipeline modules
    private var visionPipeline: VisionPipeline?
    private let sceneAnalyzer = SceneAnalyzer()
    private let planner = NavigationPlanner()

    // Core systems
    private let sensors = Sensors()
    private let audio = SpatialAudio()
    private let debugStream = DebugStream()
    private let processingQueue = DispatchQueue(label: "processing", qos: .userInteractive)

    // Grid (NavigationPlanner writes to it)
    private var grid = OccupancyGrid()

    // Published state
    @Published private(set) var isRunning = false
    @Published private(set) var fps: Int = 0
    @Published private(set) var error: String?
    @Published private(set) var isStreamConnected = false
    @Published private(set) var navigationOutput = NavigationOutput()
    @Published private(set) var visionTimeMs: Double = 0
    @Published private(set) var orientationDebug = OrientationDebug()

    // Private state
    private var frameProcessCount = 0
    private var smoothHeading: Float = 0
    private var isHeadingInitialized = false
    private var lastFrameTime: TimeInterval = 0
    private var isProcessing = false

    init() {
        print("[Engine] init")

        // Load CoreML models
        do {
            visionPipeline = try VisionPipeline()
            print("[Engine] VisionPipeline loaded")
        } catch {
            print("[Engine] VisionPipeline failed to load: \(error)")
        }

        // wire up sensor callback — drop frames if still processing previous
        sensors.onFrame = { [weak self] frame in
            guard let self, !self.isProcessing else { return }
            self.processingQueue.async {
                self.processFrame(frame)
            }
        }

        sensors.onError = { [weak self] error in
            print("[Engine] sensor error: \(error)")
            DispatchQueue.main.async {
                self?.error = error.localizedDescription
            }
        }

        // debug stream callbacks
        debugStream.onConnected = { [weak self] in
            print("[Engine] debug stream connected")
            DispatchQueue.main.async {
                self?.isStreamConnected = true
            }
        }
        debugStream.onDisconnected = { [weak self] in
            print("[Engine] debug stream disconnected")
            DispatchQueue.main.async {
                self?.isStreamConnected = false
            }
        }
    }

    func toggle() {
        print("[Engine] toggle, isRunning=\(isRunning)")
        if isRunning { stop() } else { start() }
    }

    func start() {
        print("[Engine] start()")

        guard sensors.start() else {
            print("[Engine] sensors.start() failed")
            DispatchQueue.main.async {
                self.error = "ARKit not available"
            }
            return
        }

        print("[Engine] sensors started, starting audio...")
        audio.start()

        print("[Engine] starting debug browsing...")
        debugStream.startBrowsing()

        print("[Engine] setting isRunning=true")
        DispatchQueue.main.async {
            self.isRunning = true
            self.error = nil
        }
        print("[Engine] start() complete")
    }

    func stop() {
        print("[Engine] stop()")
        sensors.stop()
        audio.stop()
        debugStream.disconnect()

        DispatchQueue.main.async {
            self.isRunning = false
            self.fps = 0
            self.navigationOutput = NavigationOutput()
        }
        print("[Engine] stop() complete")
    }

    // Connect to Mac manually by IP
    func connectDebug(host: String) {
        print("[Engine] connecting to \(host)")
        debugStream.connect(to: host)
    }

    // MARK: - Frame Processing Pipeline

    private func processFrame(_ frame: ARFrame) {
        isProcessing = true
        defer { isProcessing = false }

        let frameStart = CACurrentMediaTime()
        frameProcessCount += 1

        let pixelBuffer = frame.capturedImage
        let pose = frame.camera.transform
        let userPos = simd_make_float3(pose.columns.3)

        // Extract heading from camera forward vector
        let forward = simd_float3(-pose.columns.2.x, 0, -pose.columns.2.z)
        let rawHeading = atan2(forward.x, forward.z)

        // Smooth heading
        if !isHeadingInitialized {
            smoothHeading = rawHeading
            isHeadingInitialized = true
        } else {
            smoothHeading = smoothAngle(current: smoothHeading, target: rawHeading, alpha: ProcessingConfig.headingSmoothingAlpha)
        }
        let userHeading = smoothHeading

        // Get real camera FOV from intrinsics
        let fx = frame.camera.intrinsics[0][0]
        let width = Float(CVPixelBufferGetWidth(pixelBuffer))
        let hfov = 2 * atan(width / (2 * fx))

        // Compute delta time
        let currentTime = frame.timestamp
        let deltaTime: Float
        if lastFrameTime > 0 {
            deltaTime = Float(currentTime - lastFrameTime)
        } else {
            deltaTime = 1.0 / 60.0
        }
        lastFrameTime = currentTime

        // Orientation debug
        let (yaw, pitch, roll) = eulerYPR(from: pose)
        let debug = OrientationDebug(
            yawDeg: yaw * 180 / .pi,
            pitchDeg: pitch * 180 / .pi,
            rollDeg: roll * 180 / .pi
        )

        // 1. Run vision models (depth + segmentation)
        let visionStart = CACurrentMediaTime()
        guard let vision = visionPipeline?.process(frame: pixelBuffer) else {
            if frameProcessCount % 60 == 0 {
                print("[Engine] frame \(frameProcessCount): no vision pipeline")
            }
            return
        }
        let visionTime = (CACurrentMediaTime() - visionStart) * 1000 // ms

        // Debug: log seg/depth stats on first few frames
        if frameProcessCount <= 3 {
            let classCounts = Dictionary(grouping: vision.segLabels, by: { $0 })
                .mapValues { $0.count }
                .sorted { $0.value > $1.value }
            print("[DEBUG-SEG] Class distribution: \(classCounts.prefix(15))")
            let dMin = vision.depthData.min() ?? 0
            let dMax = vision.depthData.max() ?? 0
            print("[DEBUG] depth: \(vision.depthWidth)x\(vision.depthHeight), range: \(dMin) to \(dMax)")
            print("[DEBUG] seg: \(vision.segWidth)x\(vision.segHeight), unique classes: \(Set(vision.segLabels).sorted())")
        }

        // 2. Analyze scene (pure math, fast)
        let scene = sceneAnalyzer.analyze(
            depthData: vision.depthData,
            depthWidth: vision.depthWidth,
            depthHeight: vision.depthHeight,
            segLabels: vision.segLabels,
            segWidth: vision.segWidth,
            segHeight: vision.segHeight,
            cameraHFOV: hfov
        )

        // 3. Update grid + compute navigation
        let nav = planner.update(
            scene: scene,
            userPosition: userPos,
            userHeading: userHeading,
            deltaTime: deltaTime,
            grid: &grid
        )

        // 4. Audio feedback
        updateAudio(from: nav)

        // 5. Stream to Mac debugger
        debugStream.send(
            timestamp: frame.timestamp,
            userPosition: userPos,
            userHeading: userHeading,
            grid: grid,
            navigationOutput: nav,
            nearestObstacle: nav.nearestObstacleDistance
        )

        // 6. Debug log periodically
        if frameProcessCount % 60 == 0 {
            print("[Engine] frame \(frameProcessCount): obstacle=\(String(format: "%.2f", nav.nearestObstacleDistance))m ground=\(String(format: "%.0f%%", nav.groundConfidence * 100)) vision=\(String(format: "%.1f", visionTime))ms")
        }

        // 7. Update UI on main thread
        let frameTime = CACurrentMediaTime() - frameStart
        DispatchQueue.main.async { [sensors] in
            self.fps = sensors.fps
            self.navigationOutput = nav
            self.visionTimeMs = visionTime
            self.orientationDebug = debug
        }
    }

    // MARK: - Audio Mapping

    private func updateAudio(from nav: NavigationOutput) {
        // Map discontinuity to ElevationChange for existing audio system
        let elevationWarning: ElevationChange?
        if let disc = nav.discontinuityAhead {
            let estimatedDistance = planner.depthScale / (disc.relativeDepth + 0.001)
            if estimatedDistance < 3.0 {
                // Small magnitude = step, large = curb/danger
                let type: ElevationChangeType = disc.magnitude > 0.2 ? .curbDown : .stepDown
                elevationWarning = ElevationChange(
                    type: type,
                    position: .zero,
                    distance: estimatedDistance,
                    angle: 0,
                    heightChange: -disc.magnitude,
                    confidence: 1.0
                )
            } else {
                elevationWarning = nil
            }
        } else {
            elevationWarning = nil
        }

        // isPathBlocked → make obstacle distance very small to trigger danger beeps
        let obstacleDistance = nav.isPathBlocked ? Float(0.1) : nav.nearestObstacleDistance

        audio.update(
            nearestObstacle: obstacleDistance,
            userHeading: nav.suggestedHeading,
            elevationWarning: elevationWarning
        )
    }
}

// MARK: - Orientation debug

struct OrientationDebug {
    var yawDeg: Float = 0
    var pitchDeg: Float = 0
    var rollDeg: Float = 0

    var pitchStatus: String {
        if pitchDeg < -25 { return "TOO DOWN" }
        if pitchDeg < -8 { return "OK" }
        if pitchDeg < 5 { return "TOO LEVEL" }
        return "TOO UP"
    }
}

private func eulerYPR(from m: simd_float4x4) -> (yaw: Float, pitch: Float, roll: Float) {
    let r02 = m.columns.2.x
    let r12 = m.columns.2.y
    let r22 = m.columns.2.z
    let r10 = m.columns.0.y
    let r11 = m.columns.1.y

    let pitch = asin(clamp(-r12, -1, 1))
    let yaw = atan2(r02, r22)
    let roll = atan2(r10, r11)
    return (yaw, pitch, roll)
}

@inline(__always)
private func clamp(_ v: Float, _ lo: Float, _ hi: Float) -> Float { min(hi, max(lo, v)) }

/// Deep-copy a CVPixelBuffer so ARKit can't recycle the backing memory during inference.
private func copyPixelBuffer(_ src: CVPixelBuffer) -> CVPixelBuffer? {
    let width = CVPixelBufferGetWidth(src)
    let height = CVPixelBufferGetHeight(src)
    let format = CVPixelBufferGetPixelFormatType(src)

    var dst: CVPixelBuffer?
    let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, format, nil, &dst)
    guard status == kCVReturnSuccess, let dst else { return nil }

    CVPixelBufferLockBaseAddress(src, .readOnly)
    CVPixelBufferLockBaseAddress(dst, [])
    defer {
        CVPixelBufferUnlockBaseAddress(src, .readOnly)
        CVPixelBufferUnlockBaseAddress(dst, [])
    }

    let planeCount = CVPixelBufferGetPlaneCount(src)
    if planeCount > 0 {
        for plane in 0..<planeCount {
            let srcAddr = CVPixelBufferGetBaseAddressOfPlane(src, plane)
            let dstAddr = CVPixelBufferGetBaseAddressOfPlane(dst, plane)
            let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(src, plane)
            let h = CVPixelBufferGetHeightOfPlane(src, plane)
            memcpy(dstAddr, srcAddr, bytesPerRow * h)
        }
    } else {
        let srcAddr = CVPixelBufferGetBaseAddress(src)
        let dstAddr = CVPixelBufferGetBaseAddress(dst)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(src)
        memcpy(dstAddr, srcAddr, bytesPerRow * height)
    }

    return dst
}

@inline(__always)
private func normalizeAngle(_ a: Float) -> Float {
    var x = a
    while x > .pi { x -= 2 * .pi }
    while x < -.pi { x += 2 * .pi }
    return x
}

private func smoothAngle(current: Float, target: Float, alpha: Float) -> Float {
    let delta = normalizeAngle(target - current)
    return normalizeAngle(current + delta * alpha)
}
