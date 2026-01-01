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
    private let gridBuilder = OccupancyGridBuilder(cellSize: 0.1, gridSize: 200)
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
    
    private var frameProcessCount = 0
    private var lastUserPosition: simd_float3 = .zero
    private var lastUserHeading: Float = 0
    
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
        let userHeading = atan2(forward.x, forward.z)
        
        lastUserPosition = userPosition
        lastUserHeading = userHeading
        
        // Get mesh anchors
        let meshAnchors = sensors.getMeshAnchors()
        
        // Build occupancy grid from mesh
        var grid = gridBuilder.build(
            from: meshAnchors,
            userPosition: userPosition,
            userHeading: userHeading,
            maxDistance: 10.0
        )
        
        // Analyze for elevation changes
        let elevationChanges = ElevationAnalyzer.analyze(
            grid: grid,
            userHeading: userHeading,
            maxDistance: 5.0
        )
        
        // Mark step/curb/dropoff cells based on analyzer output (keeps builder clean).
        // This prevents false-positive coloring from noisy single-cell stats.
        for change in elevationChanges {
            let halfGrid = Float(grid.gridSize) / 2.0
            let gx = Int((change.position.x - grid.originX) / grid.cellSize + halfGrid)
            let gz = Int((change.position.y - grid.originZ) / grid.cellSize + halfGrid)
            guard gx >= 0 && gx < grid.gridSize && gz >= 0 && gz < grid.gridSize else { continue }

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
            userHeading: userHeading
        )
        
        // Calculate nearest obstacle
        let nearest = grid.nearestObstacle(
            fromX: userPosition.x,
            fromZ: userPosition.z,
            heading: userHeading
        )
        
        // Update audio feedback
        audio.update(
            nearestObstacle: nearest,
            userHeading: userHeading,
            elevationWarning: urgent
        )
        
        // Send to Mac debug viewer
        debugStream.send(
            timestamp: frame.timestamp,
            userPosition: userPosition,
            userHeading: userHeading,
            grid: grid,
            elevationChanges: elevationChanges,
            nearestObstacle: nearest
        )
        
        // Debug log periodically
        if frameProcessCount % 60 == 0 {
            print("[Engine] frame \(frameProcessCount): valid=\(grid.validCellCount) obs=\(grid.obstacleCellCount) steps=\(grid.stepCellCount) nearest=\(String(format: "%.2f", nearest))m")
        }
        
        // Update UI on main thread
        let currentFps = sensors.fps
        let stats = GridStats(
            valid: grid.validCellCount,
            obstacles: grid.obstacleCellCount,
            steps: grid.stepCellCount
        )
        
        DispatchQueue.main.async {
            self.fps = currentFps
            self.nearestObstacle = nearest
            self.elevationWarning = urgent
            self.gridStats = stats
        }
    }
}
