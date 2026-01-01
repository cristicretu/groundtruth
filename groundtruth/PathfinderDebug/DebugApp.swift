// DebugApp.swift
// Tesla-style Bird's Eye View - occupancy grid visualization
import SwiftUI
import Network

@main
struct PathfinderDebugApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1000, minHeight: 700)
        }
    }
}

struct ContentView: View {
    @StateObject private var stream = StreamReceiver()
    
    var body: some View {
        HStack(spacing: 0) {
            // Bird's Eye View (main area)
            BirdEyeView(packet: stream.packet)
                .background(Color(white: 0.05))
            
            // Sidebar
            SidebarView(stream: stream)
        }
        .background(Color.black)
    }
}

// MARK: - Bird's Eye View

struct BirdEyeView: View {
    let packet: StreamPacket?
    
    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                guard let p = packet, !p.cellStates.isEmpty else {
                    // Draw placeholder
                    context.draw(
                        Text("Waiting for data...")
                            .font(.system(size: 24, design: .monospaced))
                            .foregroundColor(.gray),
                        at: CGPoint(x: size.width/2, y: size.height/2)
                    )
                    return
                }
                
                drawGrid(context: context, size: size, packet: p)
            }
        }
    }
    
    private func drawGrid(context: GraphicsContext, size: CGSize, packet: StreamPacket) {
        let gridSize = packet.gridSize
        guard gridSize > 0 else { return }
        
        // Calculate cell size in pixels to fit the view
        let viewPadding: CGFloat = 40
        let availableSize = min(size.width - viewPadding * 2, size.height - viewPadding * 2)
        let cellPixels = availableSize / CGFloat(gridSize)
        
        let offsetX = (size.width - CGFloat(gridSize) * cellPixels) / 2
        let offsetY = (size.height - CGFloat(gridSize) * cellPixels) / 2
        
        // Draw cells
        for z in 0..<gridSize {
            for x in 0..<gridSize {
                let idx = z * gridSize + x
                guard idx < packet.cellStates.count else { continue }
                
                let state = CellState(rawValue: packet.cellStates[idx]) ?? .unknown
                let elevation = idx < packet.cellElevations.count ? Float(packet.cellElevations[idx]) / 100.0 : 0
                
                let color = colorForCell(state: state, elevation: elevation)
                
                // Flip Z for display (user looks "up" on screen)
                let displayZ = gridSize - 1 - z
                let rect = CGRect(
                    x: offsetX + CGFloat(x) * cellPixels,
                    y: offsetY + CGFloat(displayZ) * cellPixels,
                    width: cellPixels + 0.5,  // slight overlap to avoid gaps
                    height: cellPixels + 0.5
                )
                
                context.fill(Path(rect), with: .color(color))
            }
        }
        
        // Draw grid lines (every 10 cells = 1m at 10cm resolution)
        let gridLineColor = Color.white.opacity(0.1)
        let meterCells = Int(1.0 / packet.cellSize) // cells per meter
        
        for i in stride(from: 0, through: gridSize, by: meterCells) {
            // Vertical line
            let vx = offsetX + CGFloat(i) * cellPixels
            let vPath = Path { p in
                p.move(to: CGPoint(x: vx, y: offsetY))
                p.addLine(to: CGPoint(x: vx, y: offsetY + CGFloat(gridSize) * cellPixels))
            }
            context.stroke(vPath, with: .color(gridLineColor), lineWidth: 0.5)
            
            // Horizontal line
            let hy = offsetY + CGFloat(i) * cellPixels
            let hPath = Path { p in
                p.move(to: CGPoint(x: offsetX, y: hy))
                p.addLine(to: CGPoint(x: offsetX + CGFloat(gridSize) * cellPixels, y: hy))
            }
            context.stroke(hPath, with: .color(gridLineColor), lineWidth: 0.5)
        }
        
        // Draw elevation changes
        for change in packet.elevationChanges {
            let changeColor = colorForElevationType(change.type)
            
            // Convert position to grid coordinates
            let halfGrid = Float(gridSize) / 2.0
            let gx = Int((change.posX / packet.cellSize) + halfGrid)
            let gz = Int((change.posZ / packet.cellSize) + halfGrid)
            
            guard gx >= 0 && gx < gridSize && gz >= 0 && gz < gridSize else { continue }
            
            let displayZ = gridSize - 1 - gz
            let cx = offsetX + (CGFloat(gx) + 0.5) * cellPixels
            let cy = offsetY + (CGFloat(displayZ) + 0.5) * cellPixels
            
            // Draw marker
            let markerSize: CGFloat = cellPixels * 3
            let markerRect = CGRect(
                x: cx - markerSize/2,
                y: cy - markerSize/2,
                width: markerSize,
                height: markerSize
            )
            context.stroke(
                Path(ellipseIn: markerRect),
                with: .color(changeColor),
                lineWidth: 2
            )
        }
        
        // Draw user position (center of grid)
        let userX = offsetX + CGFloat(gridSize / 2) * cellPixels + cellPixels / 2
        let userY = offsetY + CGFloat(gridSize / 2) * cellPixels + cellPixels / 2
        
        // User circle
        let userRadius: CGFloat = 8
        let userRect = CGRect(
            x: userX - userRadius,
            y: userY - userRadius,
            width: userRadius * 2,
            height: userRadius * 2
        )
        context.fill(Path(ellipseIn: userRect), with: .color(.cyan))
        
        // User heading arrow
        let arrowLength: CGFloat = 25
        // Grid is already stabilized into user-forward frame (rotated on iPhone),
        // so we keep the arrow fixed pointing \"up\".
        let heading: CGFloat = 0
        
        // Arrow points "up" (negative Z) when heading is 0
        // In our display, up = negative Y
        let arrowDx = sin(heading) * arrowLength
        let arrowDy = -cos(heading) * arrowLength
        
        let arrowPath = Path { p in
            p.move(to: CGPoint(x: userX, y: userY))
            p.addLine(to: CGPoint(x: userX + arrowDx, y: userY + arrowDy))
        }
        context.stroke(arrowPath, with: .color(.cyan), lineWidth: 3)
        
        // Arrow head
        let arrowHeadSize: CGFloat = 8
        let tipX = userX + arrowDx
        let tipY = userY + arrowDy
        let headPath = Path { p in
            p.move(to: CGPoint(x: tipX, y: tipY))
            p.addLine(to: CGPoint(
                x: tipX - arrowHeadSize * CGFloat(sin(heading - 0.4)),
                y: tipY + arrowHeadSize * CGFloat(cos(heading - 0.4))
            ))
            p.addLine(to: CGPoint(
                x: tipX - arrowHeadSize * CGFloat(sin(heading + 0.4)),
                y: tipY + arrowHeadSize * CGFloat(cos(heading + 0.4))
            ))
            p.closeSubpath()
        }
        context.fill(headPath, with: .color(.cyan))
        
        // Draw scale
        let scaleY = size.height - 30
        let scaleWidth: CGFloat = CGFloat(meterCells) * cellPixels
        let scalePath = Path { p in
            p.move(to: CGPoint(x: offsetX, y: scaleY))
            p.addLine(to: CGPoint(x: offsetX + scaleWidth, y: scaleY))
        }
        context.stroke(scalePath, with: .color(.white), lineWidth: 2)
        
        context.draw(
            Text("1m")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white),
            at: CGPoint(x: offsetX + scaleWidth / 2, y: scaleY + 12)
        )
    }
    
    private func colorForCell(state: CellState, elevation: Float) -> Color {
        switch state {
        case .unknown:
            return Color(white: 0.08)
        case .free:
            // Floor - slight variation by elevation
            let brightness = 0.2 + Double(max(0, min(1, elevation / 2))) * 0.1
            return Color(white: brightness)
        case .occupied:
            return Color(red: 0.8, green: 0.2, blue: 0.2)  // Red
        case .step:
            return Color(red: 1.0, green: 0.8, blue: 0.2)  // Yellow
        case .curb:
            return Color(red: 1.0, green: 0.5, blue: 0.0)  // Orange
        case .ramp:
            return Color(red: 0.3, green: 0.7, blue: 0.3)  // Green
        case .stairs:
            return Color(red: 0.8, green: 0.6, blue: 0.2)  // Gold
        case .dropoff:
            return Color(red: 1.0, green: 0.0, blue: 0.0)  // Bright red
        }
    }
    
    private func colorForElevationType(_ type: UInt8) -> Color {
        switch type {
        case 1, 2: return .yellow      // step up/down
        case 3, 4: return .orange      // curb up/down
        case 5, 6: return .green       // ramp
        case 7: return .yellow         // stairs
        case 8: return .red            // dropoff
        default: return .white
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @ObservedObject var stream: StreamReceiver
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title
            Text("PATHFINDER")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
            
            Divider().background(Color.gray)
            
            // Connection status
            HStack {
                Circle()
                    .fill(stream.connected ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                Text(stream.connected ? "Connected" : "Waiting...")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.gray)
            }
            
            // Stats
            if let p = stream.packet {
                VStack(alignment: .leading, spacing: 8) {
                    statRow("FPS", "\(stream.fps)")
                    statRow("Grid", "\(p.gridSize)×\(p.gridSize)")
                    statRow("Cell", "\(Int(p.cellSize * 100))cm")
                    
                    Divider().background(Color.gray)
                    
                    statRow("Valid", "\(p.validCells)")
                    statRow("Obstacles", "\(p.obstacleCells)", color: .red)
                    statRow("Steps", "\(p.stepCells)", color: .yellow)
                    
                    Divider().background(Color.gray)
                    
                    statRow("Nearest", String(format: "%.2fm", p.nearestObstacle))
                    statRow("Floor", String(format: "%.2fm", p.floorHeight))
                    statRow("Heading", String(format: "%.0f°", p.userHeading * 180 / .pi))
                }
            }
            
            Divider().background(Color.gray)
            
            // Elevation warnings
            if let p = stream.packet, !p.elevationChanges.isEmpty {
                Text("WARNINGS")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.orange)
                
                ForEach(Array(p.elevationChanges.prefix(5).enumerated()), id: \.offset) { _, change in
                    warningRow(change)
                }
            }
            
            Spacer()
            
            // Legend
            VStack(alignment: .leading, spacing: 4) {
                Text("LEGEND")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
                
                legendRow(Color(white: 0.2), "Floor")
                legendRow(Color.red, "Obstacle")
                legendRow(Color.yellow, "Step")
                legendRow(Color.orange, "Curb")
                legendRow(Color.green, "Ramp")
            }
            
            Divider().background(Color.gray)
            
            // IP
            Text(stream.localIP)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.gray)
        }
        .padding()
        .frame(width: 180)
        .background(Color(white: 0.1))
    }
    
    private func statRow(_ label: String, _ value: String, color: Color = .cyan) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(color)
        }
    }
    
    private func warningRow(_ change: StreamElevationChange) -> some View {
        HStack {
            Circle()
                .fill(change.type == 8 ? Color.red : Color.yellow)
                .frame(width: 6, height: 6)
            Text(elevationTypeName(change.type))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white)
            Spacer()
            Text(String(format: "%.1fm", change.distance))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.gray)
        }
    }
    
    private func legendRow(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(color)
                .frame(width: 12, height: 12)
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.gray)
        }
    }
    
    private func elevationTypeName(_ type: UInt8) -> String {
        switch type {
        case 1: return "Step Up"
        case 2: return "Step Down"
        case 3: return "Curb Up"
        case 4: return "Curb Down"
        case 5: return "Ramp Up"
        case 6: return "Ramp Down"
        case 7: return "Stairs"
        case 8: return "DROPOFF"
        default: return "Unknown"
        }
    }
}

// MARK: - Cell State (matches iPhone)

enum CellState: UInt8 {
    case unknown = 0
    case free = 1
    case occupied = 2
    case step = 3
    case curb = 4
    case ramp = 5
    case stairs = 6
    case dropoff = 7
}

// MARK: - Network

class StreamReceiver: ObservableObject {
    @Published var packet: StreamPacket?
    @Published var connected = false
    @Published var fps = 0
    var localIP: String
    
    private var listener: NWListener?
    private var conn: NWConnection?
    private var buf: [UInt8] = []
    private var frameCount = 0
    private var lastSec = Date()
    
    init() {
        localIP = Self.getIP() ?? "?"
        startServer()
    }
    
    static func getIP() -> String? {
        var addr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addr) == 0, let first = addr else { return nil }
        defer { freeifaddrs(addr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let iface = ptr.pointee
            if iface.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: iface.ifa_name)
                if name == "en0" || name == "en1" {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(iface.ifa_addr, socklen_t(iface.ifa_addr.pointee.sa_len),
                               &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                    return String(cString: host)
                }
            }
        }
        return nil
    }
    
    func startServer() {
        let params = NWParameters.tcp
        listener = try? NWListener(using: params, on: 8765)
        listener?.newConnectionHandler = { [weak self] c in self?.handle(c) }
        listener?.start(queue: .global())
        print("[server] listening on \(localIP):8765")
    }
    
    func handle(_ c: NWConnection) {
        print("[server] new connection")
        conn?.cancel()
        conn = c
        c.stateUpdateHandler = { [weak self] s in
            print("[server] state: \(s)")
            DispatchQueue.main.async { self?.connected = (s == .ready) }
        }
        c.start(queue: .global())
        recv(c)
    }
    
    func recv(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 131072) { [weak self] data, _, done, err in
            if let err = err {
                print("[recv] error: \(err)")
                return
            }
            guard let self = self, let data = data else { return }
            
            self.buf.append(contentsOf: data)
            self.process()
            if !done { self.recv(c) }
        }
    }
    
    func process() {
        while buf.count >= 4 {
            let len = Int(buf[0]) << 24 | Int(buf[1]) << 16 | Int(buf[2]) << 8 | Int(buf[3])
            guard len > 0 && len < 10_000_000 else {
                print("[recv] invalid length: \(len), clearing buffer")
                buf.removeAll()
                return
            }
            guard buf.count >= 4 + len else { break }
            
            let pkt = Data(buf[4..<4+len])
            buf.removeFirst(4 + len)
            
            do {
                let p = try JSONDecoder().decode(StreamPacket.self, from: pkt)
                DispatchQueue.main.async {
                    self.packet = p
                    self.tick()
                }
            } catch {
                print("[recv] decode error: \(error)")
            }
        }
    }
    
    func tick() {
        frameCount += 1
        let now = Date()
        if now.timeIntervalSince(lastSec) >= 1 {
            fps = frameCount
            frameCount = 0
            lastSec = now
        }
    }
}

// MARK: - Data Structures (match iPhone)

struct StreamElevationChange: Codable {
    var type: UInt8
    var posX: Float
    var posZ: Float
    var distance: Float
    var angle: Float
    var heightChange: Float
}

struct StreamPacket: Codable {
    var timestamp: Double = 0
    var userPosition: [Float] = [0, 0, 0]
    var userHeading: Float = 0
    var nearestObstacle: Float = .infinity
    var floorHeight: Float = 0
    
    var gridSize: Int = 200
    var cellSize: Float = 0.1
    
    var cellStates: [UInt8] = []
    var cellElevations: [Int8] = []
    
    var validCells: Int = 0
    var obstacleCells: Int = 0
    var stepCells: Int = 0
    
    var elevationChanges: [StreamElevationChange] = []
}
