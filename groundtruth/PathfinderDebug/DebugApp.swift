// DebugApp.swift
// Mac companion app for FSD-style visualization
import SwiftUI
import Network
import simd
import AppKit

@main
struct PathfinderDebugApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            DebugView()
                .frame(minWidth: 900, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

// Make app appear in dock
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct DebugView: View {
    @StateObject private var receiver = StreamReceiver()
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            HStack(spacing: 0) {
                // FSD-style world view - shows the grid/obstacles
                WorldView(packet: receiver.latestPacket)
                    .frame(maxWidth: .infinity)
                
                // Side panel
                VStack(alignment: .leading, spacing: 16) {
                    Text("PATHFINDER DEBUG")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    
                    Divider().background(Color.gray)
                    
                    // Connection status
                    HStack {
                        Circle()
                            .fill(receiver.isConnected ? Color.green : Color.red)
                            .frame(width: 12, height: 12)
                        Text(receiver.isConnected ? "Connected" : "Waiting...")
                            .foregroundColor(.white)
                    }
                    
                    if let packet = receiver.latestPacket {
                        VStack(alignment: .leading, spacing: 8) {
                            statRow("FPS", "\(receiver.fps)")
                            statRow("Nearest", String(format: "%.2fm", packet.nearestObstacle))
                            statRow("Obstacles", "\(packet.obstacles.count)")
                            statRow("Curbs", "\(packet.obstacles.filter { $0.isCurb }.count)")
                            statRow("Heading", String(format: "%.1f°", packet.userHeading * 180 / .pi))
                        }
                        
                        Divider().background(Color.gray)
                        
                        // Depth preview - larger
                        if let depthImage = receiver.depthImage {
                            Text("Depth Map (\(Int(depthImage.size.width))x\(Int(depthImage.size.height)))")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Image(nsImage: depthImage)
                                .resizable()
                                .interpolation(.none)  // pixel-perfect, no blur
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 200)
                                .cornerRadius(8)
                                .border(Color.gray.opacity(0.3), width: 1)
                        }
                    } else {
                        Text("No data yet...")
                            .foregroundColor(.gray)
                            .italic()
                    }
                    
                    Spacer()
                    
                    // Connection info
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Connect iPhone to:")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text("\(receiver.localIP):8765")
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(.cyan)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                }
                .padding()
                .frame(width: 220)
                .background(Color(white: 0.1))
            }
        }
        .onAppear {
            receiver.startListening()
        }
    }
    
    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.gray)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.white)
        }
    }
}

// FSD-style bird's eye world view
struct WorldView: View {
    let packet: StreamPacket?
    
    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height * 0.75)
                let scale: CGFloat = min(size.width, size.height) / 12  // ~6m visible each direction
                
                // Background gradient (darker at top = further away)
                let gradient = Gradient(colors: [
                    Color(white: 0.05),
                    Color(white: 0.1)
                ])
                context.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height))
                )
                
                // Grid lines
                drawGrid(context: context, center: center, size: size, scale: scale)
                
                // Distance rings
                drawDistanceRings(context: context, center: center, scale: scale)
                
                // Draw obstacles
                if let packet = packet {
                    drawObstacles(context: context, center: center, scale: scale, packet: packet)
                }
                
                // User indicator (you are here)
                drawUser(context: context, center: center)
                
                // FOV indicator
                drawFOV(context: context, center: center, scale: scale)
            }
        }
    }
    
    private func drawGrid(context: GraphicsContext, center: CGPoint, size: CGSize, scale: CGFloat) {
        var gridPath = Path()
        
        // Vertical lines (1m spacing)
        for i in -6...6 {
            let x = center.x + CGFloat(i) * scale
            gridPath.move(to: CGPoint(x: x, y: 0))
            gridPath.addLine(to: CGPoint(x: x, y: size.height))
        }
        
        // Horizontal lines
        for i in -8...2 {
            let y = center.y + CGFloat(i) * scale
            gridPath.move(to: CGPoint(x: 0, y: y))
            gridPath.addLine(to: CGPoint(x: size.width, y: y))
        }
        
        context.stroke(gridPath, with: .color(.gray.opacity(0.15)), lineWidth: 1)
    }
    
    private func drawDistanceRings(context: GraphicsContext, center: CGPoint, scale: CGFloat) {
        for meters in [1, 2, 3, 4, 5] {
            let radius = CGFloat(meters) * scale
            let rect = CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            
            // Ring
            context.stroke(
                Path(ellipseIn: rect),
                with: .color(.gray.opacity(0.25)),
                lineWidth: 1
            )
            
            // Label
            context.draw(
                Text("\(meters)m")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.gray.opacity(0.6)),
                at: CGPoint(x: center.x + radius + 12, y: center.y)
            )
        }
    }
    
    private func drawObstacles(context: GraphicsContext, center: CGPoint, scale: CGFloat, packet: StreamPacket) {
        let heading = CGFloat(packet.userHeading)
        
        for obstacle in packet.obstacles {
            // Position relative to user (already in user's coordinate frame from WorldModel)
            // Rotate by heading so forward is always up on screen
            let x = CGFloat(obstacle.x) * cos(-heading) - CGFloat(obstacle.z) * sin(-heading)
            let z = CGFloat(obstacle.x) * sin(-heading) + CGFloat(obstacle.z) * cos(-heading)
            
            let screenX = center.x + x * scale
            let screenY = center.y - z * scale  // negative because screen Y is down
            
            // Skip if off screen
            guard screenX > -50 && screenX < 1000 && screenY > -50 && screenY < 1000 else { continue }
            
            // Color and size based on type
            let color: Color = obstacle.isCurb ? .yellow : .red
            let baseRadius: CGFloat = obstacle.isCurb ? 4 : 6
            
            // Size based on distance (closer = bigger)
            let distanceFactor = max(0.5, min(2.0, 3.0 / CGFloat(obstacle.distance)))
            let radius = baseRadius * distanceFactor
            
            let rect = CGRect(
                x: screenX - radius,
                y: screenY - radius,
                width: radius * 2,
                height: radius * 2
            )
            
            // Glow effect for close obstacles
            if obstacle.distance < 2.0 {
                let glowRect = rect.insetBy(dx: -4, dy: -4)
                context.fill(
                    Path(ellipseIn: glowRect),
                    with: .color(color.opacity(0.3))
                )
            }
            
            context.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.9)))
        }
    }
    
    private func drawUser(context: GraphicsContext, center: CGPoint) {
        // Triangle pointing up (forward)
        let userPath = Path { path in
            path.move(to: CGPoint(x: center.x, y: center.y - 15))
            path.addLine(to: CGPoint(x: center.x - 10, y: center.y + 8))
            path.addLine(to: CGPoint(x: center.x + 10, y: center.y + 8))
            path.closeSubpath()
        }
        
        // Glow
        context.fill(userPath.strokedPath(.init(lineWidth: 6)), with: .color(.cyan.opacity(0.3)))
        context.fill(userPath, with: .color(.cyan))
    }
    
    private func drawFOV(context: GraphicsContext, center: CGPoint, scale: CGFloat) {
        // Field of view cone (approximate LiDAR FOV ~70°)
        let fovAngle: CGFloat = .pi / 2.5  // ~70 degrees
        let fovLength: CGFloat = 5 * scale
        
        var fovPath = Path()
        fovPath.move(to: center)
        fovPath.addLine(to: CGPoint(
            x: center.x - sin(fovAngle / 2) * fovLength,
            y: center.y - cos(fovAngle / 2) * fovLength
        ))
        fovPath.addLine(to: CGPoint(
            x: center.x + sin(fovAngle / 2) * fovLength,
            y: center.y - cos(fovAngle / 2) * fovLength
        ))
        fovPath.closeSubpath()
        
        context.fill(fovPath, with: .color(.cyan.opacity(0.05)))
        context.stroke(fovPath, with: .color(.cyan.opacity(0.2)), lineWidth: 1)
    }
}

// Network receiver
class StreamReceiver: ObservableObject {
    private var listener: NWListener?
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "receiver")
    
    @Published var isConnected = false
    @Published var latestPacket: StreamPacket?
    @Published var depthImage: NSImage?
    @Published var fps: Int = 0
    @Published var localIP: String = "..."
    
    private var frameCount = 0
    private var lastFPSTime = Date()
    private let bufferLock = NSLock()
    
    func startListening(port: UInt16 = 8765) {
        localIP = getLocalIP() ?? "unknown"
        
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            listener?.newConnectionHandler = { [weak self] conn in
                self?.handleConnection(conn)
            }
            listener?.start(queue: queue)
            print("[Mac] Listening on \(localIP):\(port)")
        } catch {
            print("[Mac] Listener error: \(error)")
        }
    }
    
    private func getLocalIP() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                               &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        return address
    }
    
    private func handleConnection(_ connection: NWConnection) {
        print("[Mac] New connection")
        
        DispatchQueue.main.async {
            self.connection?.cancel()
            self.connection = connection
        }
        
        connection.stateUpdateHandler = { [weak self] state in
            print("[Mac] Connection state: \(state)")
            DispatchQueue.main.async {
                self?.isConnected = (state == .ready)
            }
        }
        
        connection.start(queue: queue)
        receiveLoop(connection)
    }
    
    // Use byte array instead of Data to avoid Swift's Data slicing issues
    private var byteBuffer: [UInt8] = []
    
    private func receiveLoop(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                print("[Mac] receive error: \(error)")
            }
            
            if let data = data, !data.isEmpty {
                print("[Mac] received \(data.count) bytes")
                self.bufferLock.lock()
                self.byteBuffer.append(contentsOf: data)
                self.bufferLock.unlock()
                self.processPackets()
            }
            
            if isComplete {
                print("[Mac] receive complete (connection closed)")
            }
            
            if !isComplete && error == nil {
                self.receiveLoop(connection)
            } else {
                print("[Mac] stopping receive loop: isComplete=\(isComplete), error=\(String(describing: error))")
            }
        }
    }
    
    private func processPackets() {
        bufferLock.lock()
        
        while byteBuffer.count >= 4 {
            // Read length (big endian)
            let length = (UInt32(byteBuffer[0]) << 24) |
                        (UInt32(byteBuffer[1]) << 16) |
                        (UInt32(byteBuffer[2]) << 8) |
                         UInt32(byteBuffer[3])
            
            let packetSize = Int(length)
            let totalNeeded = 4 + packetSize
            
            guard byteBuffer.count >= totalNeeded else { break }
            
            // Extract packet bytes
            let packetBytes = Array(byteBuffer[4..<totalNeeded])
            byteBuffer.removeFirst(totalNeeded)
            
            bufferLock.unlock()
            
            // Decode
            let packetData = Data(packetBytes)
            if let packet = try? JSONDecoder().decode(StreamPacket.self, from: packetData) {
                DispatchQueue.main.async { [weak self] in
                    self?.latestPacket = packet
                    self?.updateFPS()
                    self?.updateDepthImage(packet)
                }
            }
            
            bufferLock.lock()
        }
        
        bufferLock.unlock()
    }
    
    private func updateFPS() {
        frameCount += 1
        let now = Date()
        if now.timeIntervalSince(lastFPSTime) >= 1.0 {
            fps = frameCount
            frameCount = 0
            lastFPSTime = now
        }
    }
    
    private func updateDepthImage(_ packet: StreamPacket) {
        guard let depthData = packet.depthData,
              packet.depthWidth > 0 && packet.depthHeight > 0 else { return }
        
        let width = Int(packet.depthWidth)
        let height = Int(packet.depthHeight)
        
        var pixels = [UInt8](repeating: 0, count: width * height)
        depthData.withUnsafeBytes { ptr in
            let floats = ptr.bindMemory(to: Float32.self)
            for i in 0..<min(floats.count, pixels.count) {
                let depth = floats[i]
                let normalized = min(max(depth / 5.0, 0), 1)
                pixels[i] = UInt8((1 - normalized) * 255)
            }
        }
        
        let colorSpace = CGColorSpaceCreateDeviceGray()
        if let provider = CGDataProvider(data: Data(pixels) as CFData),
           let cgImage = CGImage(
               width: width, height: height,
               bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
               space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: 0),
               provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
           ) {
            depthImage = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
        }
    }
}

// Packet structure (must match iPhone)
struct StreamPacket: Codable {
    var timestamp: Double = 0
    var userPosition: [Float] = [0, 0, 0]
    var userHeading: Float = 0
    var nearestObstacle: Float = .infinity
    var obstacleCount: UInt16 = 0
    var obstacles: [Obstacle] = []
    var depthWidth: UInt16 = 0
    var depthHeight: UInt16 = 0
    var depthData: Data? = nil
    
    struct Obstacle: Codable {
        var x: Float
        var z: Float
        var distance: Float
        var isCurb: Bool
    }
}
