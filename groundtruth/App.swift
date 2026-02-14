// App.swift
// Minimal UI - headless navigation, no camera preview
import SwiftUI
import Combine
import ARKit

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
                
                // stats (debug)
                if engine.isRunning {
                    statsView
                }
                
                // elevation warning
                if let warning = engine.elevationWarning {
                    elevationWarningView(warning)
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
                
                if engine.nearestObstacle < .infinity {
                    Text(String(format: "%.1fm", engine.nearestObstacle))
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .foregroundColor(statusColor)
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(16)
    }
    
    private func elevationWarningView(_ warning: ElevationChange) -> some View {
        HStack {
            Image(systemName: warning.isDanger ? "exclamationmark.triangle.fill" : "arrow.up.right")
                .foregroundColor(warning.isDanger ? .red : .yellow)
            
            VStack(alignment: .leading) {
                Text(warning.shortDescription)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(warning.isDanger ? .red : .yellow)
                
                Text(String(format: "%.1fm ahead", warning.distance))
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
    }
    
    private var statusColor: Color {
        let dist = engine.nearestObstacle
        if dist < 0.5 { return .red }
        if dist < 1.0 { return .orange }
        if dist < 2.0 { return .yellow }
        return .green
    }
    
    private var statusText: String {
        let dist = engine.nearestObstacle
        if dist == .infinity { return "CLEAR" }
        if dist < 0.5 { return "STOP" }
        if dist < 1.0 { return "CLOSE" }
        if dist < 2.0 { return "CAUTION" }
        return "AHEAD"
    }
    
    private var statsView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("FPS: \(engine.fps)")
            Text("Valid cells: \(engine.gridStats.valid)")
            Text("Obstacles: \(engine.gridStats.obstacles)")
            Text("Steps: \(engine.gridStats.steps)")
            Divider().overlay(Color.gray.opacity(0.4))
            Text(String(format: "Yaw: %.0f°", engine.orientationDebug.yawDeg))
            Text(String(format: "Pitch: %.0f° (%@)", engine.orientationDebug.pitchDeg, engine.orientationDebug.pitchStatus))
            Text(String(format: "Roll: %.0f°", engine.orientationDebug.rollDeg))
        }
        .font(.system(size: 12, design: .monospaced))
        .foregroundColor(.green)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.black.opacity(0.8))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}

// Grid stats for UI
struct GridStats {
    var valid: Int = 0
    var obstacles: Int = 0
    var steps: Int = 0
}

// The navigation engine - ties everything together
final class NavigationEngine: ObservableObject {
    private let sensors = Sensors()
    private let gridBuilder = OccupancyGridBuilder()  // Uses GridConfig defaults
    private let audio = SpatialAudio()
    private let debugStream = DebugStream()
    private let processingQueue = DispatchQueue(label: "processing", qos: .userInteractive)
    
    @Published private(set) var isRunning = false
    @Published private(set) var fps: Int = 0
    @Published private(set) var error: String?
    @Published private(set) var isStreamConnected = false
    @Published private(set) var nearestObstacle: Float = .infinity
    @Published private(set) var elevationWarning: ElevationChange?
    @Published private(set) var gridStats = GridStats()
    @Published private(set) var orientationDebug = OrientationDebug()
    
    private var frameProcessCount = 0
    private var lastUserPosition: simd_float3 = .zero
    private var lastUserHeading: Float = 0
    private var smoothHeading: Float = 0
    private var isHeadingInitialized = false
    private var lastFrameTime: TimeInterval = 0
    
    init() {
        print("[Engine] init")
        
        // wire up sensor callback - runs on sensor queue
        sensors.onFrame = { [weak self] frame in
            // Process on separate queue to not block sensor queue
            self?.processingQueue.async {
                self?.processFrame(frame)
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
        if isRunning {
            stop()
        } else {
            start()
        }
    }
    
    func start() {
        print("[Engine] start()")
        
        guard sensors.start() else {
            print("[Engine] sensors.start() failed")
            DispatchQueue.main.async {
                self.error = "LiDAR not available"
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
            self.nearestObstacle = .infinity
            self.elevationWarning = nil
            self.gridStats = GridStats()
        }
        print("[Engine] stop() complete")
    }
    
    // Connect to Mac manually by IP
    func connectDebug(host: String) {
        print("[Engine] connecting to \(host)")
        debugStream.connect(to: host)
    }
    
    // Called on processing queue
    private func processFrame(_ frame: ARFrame) {
        frameProcessCount += 1
        
        // Extract user pose
        let transform = frame.camera.transform
        let userPosition = simd_float3(
            transform.columns.3.x,
            transform.columns.3.y,
            transform.columns.3.z
        )
        let forward = simd_float3(
            -transform.columns.2.x,
            0,
            -transform.columns.2.z
        )
        let rawHeading = atan2(forward.x, forward.z)

        // Smooth heading for BEV stability (reduces jitter from ARKit pose noise).
        if !isHeadingInitialized {
            smoothHeading = rawHeading
            isHeadingInitialized = true
        } else {
            smoothHeading = smoothAngle(current: smoothHeading, target: rawHeading, alpha: ProcessingConfig.headingSmoothingAlpha)
        }
        
        lastUserPosition = userPosition
        lastUserHeading = smoothHeading

        // Orientation debug (pitch/roll/yaw in degrees) for chest-mount setup.
        let (yaw, pitch, roll) = eulerYPR(from: transform)
        let debug = OrientationDebug(
            yawDeg: yaw * 180 / .pi,
            pitchDeg: pitch * 180 / .pi,
            rollDeg: roll * 180 / .pi
        )
        
        // Get mesh anchors
        let meshAnchors = sensors.getMeshAnchors()
        
        // Compute delta time
        let currentTime = frame.timestamp
        let deltaTime: Float
        if lastFrameTime > 0 {
            deltaTime = Float(currentTime - lastFrameTime)
        } else {
            deltaTime = 1.0 / 60.0
        }
        lastFrameTime = currentTime

        // Build occupancy grid from mesh
        var grid = gridBuilder.build(
            from: meshAnchors,
            userPosition: userPosition,
            userHeading: smoothHeading,
            deltaTime: deltaTime
        )
        
        // Analyze for elevation changes
        let elevationChanges = ElevationAnalyzer.analyze(
            grid: grid,
            userHeading: smoothHeading,
            maxDistance: 5.0
        )
        
        // Mark step/curb/dropoff cells based on analyzer output (keeps builder clean).
        // This prevents false-positive coloring from noisy single-cell stats.
        for change in elevationChanges {
            guard let (gx, gz) = grid.worldToGrid(change.position.x, change.position.y) else { continue }

            let mapped: CellState
            switch change.type {
            case .stepUp, .stepDown: mapped = .step
            case .curbUp, .curbDown: mapped = .curb
            case .rampUp, .rampDown: mapped = .ramp
            case .stairs: mapped = .stairs
            case .dropoff: mapped = .dropoff
            default: mapped = .unknown
            }

            if mapped != .unknown {
                // Only override free/unknown. Never overwrite occupied.
                if grid.cells[gx][gz].state != .occupied {
                    grid.cells[gx][gz].state = mapped
                }
            }
        }

        // Get most urgent warning
        let urgent = ElevationAnalyzer.getMostUrgent(
            elevationChanges,
            userHeading: smoothHeading
        )
        
        // Calculate nearest obstacle
        let nearest = grid.nearestObstacle(
            fromX: userPosition.x,
            fromZ: userPosition.z,
            heading: smoothHeading
        )
        
        // Update audio feedback
        audio.update(
            nearestObstacle: nearest,
            userHeading: smoothHeading,
            elevationWarning: urgent
        )
        
        // Send to Mac debug viewer
        debugStream.send(
            timestamp: frame.timestamp,
            userPosition: userPosition,
            userHeading: smoothHeading,
            grid: grid,
            elevationChanges: elevationChanges,
            nearestObstacle: nearest
        )
        
        // Debug log periodically
        if frameProcessCount % 60 == 0 {
            print("[Engine] frame \(frameProcessCount): valid=\(grid.validCellCount) obs=\(grid.obstacleCellCount) steps=\(grid.stepCellCount) nearest=\(String(format: "%.2f", nearest))m")
        }
        
        // Update UI on main thread
        let stats = GridStats(
            valid: grid.validCellCount,
            obstacles: grid.obstacleCellCount,
            steps: grid.stepCellCount
        )
        
        DispatchQueue.main.async { [sensors] in
            // Read fps on main thread since it's @MainActor
            self.fps = sensors.fps
            self.nearestObstacle = nearest
            self.elevationWarning = urgent
            self.gridStats = stats
            self.orientationDebug = debug
        }
    }
}

// MARK: - Orientation debug

struct OrientationDebug {
    var yawDeg: Float = 0
    var pitchDeg: Float = 0
    var rollDeg: Float = 0

    var pitchStatus: String {
        // For chest mount: we want slight downward tilt (10-20°).
        if pitchDeg < -25 { return "TOO DOWN" }
        if pitchDeg < -8 { return "OK" }
        if pitchDeg < 5 { return "TOO LEVEL" }
        return "TOO UP"
    }
}

private func eulerYPR(from m: simd_float4x4) -> (yaw: Float, pitch: Float, roll: Float) {
    // Extract yaw/pitch/roll from rotation matrix.
    // ARKit: right-handed, y-up. This gives a stable approximation for UI/debug.
    let r00 = m.columns.0.x, r01 = m.columns.1.x, r02 = m.columns.2.x
    let r10 = m.columns.0.y, r11 = m.columns.1.y, r12 = m.columns.2.y
    let r20 = m.columns.0.z, r21 = m.columns.1.z, r22 = m.columns.2.z

    // Yaw around Y, Pitch around X, Roll around Z (one common convention).
    // Guard against numerical issues.
    let pitch = asin(clamp(-r12, -1, 1))
    let yaw = atan2(r02, r22)
    let roll = atan2(r10, r11)
    return (yaw, pitch, roll)
}

@inline(__always)
private func clamp(_ v: Float, _ lo: Float, _ hi: Float) -> Float { min(hi, max(lo, v)) }

@inline(__always)
private func normalizeAngle(_ a: Float) -> Float {
    var x = a
    while x > .pi { x -= 2 * .pi }
    while x < -.pi { x += 2 * .pi }
    return x
}

private func smoothAngle(current: Float, target: Float, alpha: Float) -> Float {
    // Smooth on the shortest arc.
    let delta = normalizeAngle(target - current)
    return normalizeAngle(current + delta * alpha)
}
