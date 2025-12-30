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
    @State private var debugIP = ""
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
                
                if engine.world.nearestObstacle < .infinity {
                    Text(String(format: "%.1fm", engine.world.nearestObstacle))
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
        let dist = engine.world.nearestObstacle
        if dist < 0.5 { return .red }
        if dist < 1.0 { return .orange }
        if dist < 2.0 { return .yellow }
        return .green
    }
    
    private var statusText: String {
        let dist = engine.world.nearestObstacle
        if dist == .infinity { return "CLEAR" }
        if dist < 0.5 { return "STOP" }
        if dist < 1.0 { return "CLOSE" }
        if dist < 2.0 { return "CAUTION" }
        return "AHEAD"
    }
    
    private var statsView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("FPS: \(engine.fps)")
            Text("Obstacles: \(engine.world.obstacles.count)")
            Text("Curbs: \(engine.world.obstacles.filter { $0.isCurb }.count)")
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

// The navigation engine - ties everything together
// NOT @MainActor - we handle threading manually for performance
final class NavigationEngine: ObservableObject {
    private let sensors = Sensors()
    private let worldBuilder = WorldBuilder()
    private let audio = SpatialAudio()
    private let debugStream = DebugStream()
    private let processingQueue = DispatchQueue(label: "processing", qos: .userInteractive)
    
    @Published private(set) var isRunning = false
    @Published private(set) var world = WorldModel.empty
    @Published private(set) var fps: Int = 0
    @Published private(set) var error: String?
    @Published private(set) var isStreamConnected = false
    
    private var frameProcessCount = 0
    
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
            self.world = WorldModel.empty
            self.fps = 0
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
        if frameProcessCount % 60 == 0 {
            print("[Engine] processed \(frameProcessCount) frames")
        }
        
        // extract depth points for world model
        let depthPoints = Depth.extractPoints(from: frame, downsample: 4)
        
        // build world model
        let newWorld = worldBuilder.update(
            points: depthPoints,
            transform: frame.camera.transform,
            timestamp: frame.timestamp
        )
        
        // update audio
        audio.update(world: newWorld)
        
        // build occupancy grid from mesh (clean 2D representation)
        let meshAnchors = sensors.getMeshAnchors()
        let grid = MeshExtractor.buildOccupancyGrid(
            from: meshAnchors,
            userPosition: newWorld.userPosition,
            maxDistance: 4.0
        )

        // extract point cloud for 3D visualization
        let pointCloud = MeshExtractor.extractPointCloud(
            from: meshAnchors,
            userPosition: newWorld.userPosition,
            floorY: newWorld.userPosition.y - 1.6  // assume ~1.6m phone height
        )

        // send to Mac debug viewer
        debugStream.send(frame: frame, world: newWorld, grid: grid, points: pointCloud)
        
        // update UI on main thread
        let currentFps = sensors.fps
        DispatchQueue.main.async {
            self.world = newWorld
            self.fps = currentFps
        }
    }
}
