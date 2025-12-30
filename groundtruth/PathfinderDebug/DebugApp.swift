// DebugApp.swift
// Mac companion app for FSD-style 3D point cloud visualization
import SwiftUI
import SceneKit
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
                // 3D Point Cloud View
                PointCloudView(packet: receiver.latestPacket)
                    .frame(maxWidth: .infinity)

                // Side panel
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundColor(.cyan)
                        Text("PATHFINDER")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }

                    Divider().background(Color.gray)

                    // Connection status
                    HStack {
                        Circle()
                            .fill(receiver.isConnected ? Color.green : Color.red)
                            .frame(width: 12, height: 12)
                        Text(receiver.isConnected ? "LIVE" : "Waiting...")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(receiver.isConnected ? .green : .gray)
                    }

                    if let packet = receiver.latestPacket {
                        VStack(alignment: .leading, spacing: 8) {
                            statRow("FPS", "\(receiver.fps)")
                            statRow("RANGE", String(format: "%.1fm", packet.nearestObstacle))

                            Divider().background(Color.gray.opacity(0.5))

                            // Heading display
                            HStack {
                                Image(systemName: "arrow.up")
                                    .rotationEffect(.radians(Double(packet.userHeading)))
                                    .foregroundColor(.cyan)
                                Text(String(format: "%.0f°", packet.userHeading * 180 / .pi))
                                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                            }

                            Divider().background(Color.gray.opacity(0.5))

                            Text("WORLD MAP")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.gray)
                            statRow("Points", "\(packet.points.count)")
                            statRow("Grid", "\(packet.gridSize)x\(packet.gridSize)")
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
                .frame(width: 200)
                .background(Color(white: 0.08))
            }
        }
        .onAppear {
            receiver.startListening()
        }
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.gray)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(.cyan)
        }
    }
}

// MARK: - 3D Point Cloud View

struct PointCloudView: NSViewRepresentable {
    let packet: StreamPacket?

    func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = context.coordinator.scene
        scnView.backgroundColor = NSColor(white: 0.05, alpha: 1)
        scnView.antialiasingMode = .multisampling4X
        scnView.allowsCameraControl = true  // Let user rotate/zoom
        scnView.autoenablesDefaultLighting = false
        return scnView
    }

    func updateNSView(_ scnView: SCNView, context: Context) {
        context.coordinator.updatePointCloud(packet: packet)
    }

    func makeCoordinator() -> PointCloudCoordinator {
        PointCloudCoordinator()
    }
}

class PointCloudCoordinator {
    let scene = SCNScene()
    private var pointCloudNode: SCNNode?
    private var userNode: SCNNode?
    private var gridNode: SCNNode?

    init() {
        setupScene()
    }

    private func setupScene() {
        scene.background.contents = NSColor(white: 0.02, alpha: 1)

        // Camera - third person view behind and above
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zNear = 0.1
        cameraNode.camera?.zFar = 100
        cameraNode.camera?.fieldOfView = 60
        cameraNode.position = SCNVector3(0, 4, 6)  // Behind and above
        cameraNode.look(at: SCNVector3(0, 0, -2))  // Look forward
        scene.rootNode.addChildNode(cameraNode)

        // Ambient light
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 500
        ambientLight.light?.color = NSColor.white
        scene.rootNode.addChildNode(ambientLight)

        // Ground grid
        setupGrid()

        // User indicator
        setupUserIndicator()
    }

    private func setupGrid() {
        let gridNode = SCNNode()

        // Create grid lines
        for i in -5...5 {
            let dist = Float(i)

            // Lines parallel to Z (forward)
            let lineZ = createLine(
                from: SCNVector3(dist, 0, -5),
                to: SCNVector3(dist, 0, 5),
                color: NSColor(white: 0.15, alpha: 1)
            )
            gridNode.addChildNode(lineZ)

            // Lines parallel to X (sideways)
            let lineX = createLine(
                from: SCNVector3(-5, 0, dist),
                to: SCNVector3(5, 0, dist),
                color: NSColor(white: 0.15, alpha: 1)
            )
            gridNode.addChildNode(lineX)
        }

        // Distance rings
        for meters in [1, 2, 3, 4, 5] {
            let ring = createRing(radius: Float(meters), color: NSColor(white: 0.2, alpha: 1))
            gridNode.addChildNode(ring)

            // Distance label
            let text = SCNText(string: "\(meters)m", extrusionDepth: 0)
            text.font = NSFont.monospacedSystemFont(ofSize: 0.15, weight: .regular)
            text.firstMaterial?.diffuse.contents = NSColor(white: 0.4, alpha: 1)
            let textNode = SCNNode(geometry: text)
            textNode.position = SCNVector3(Float(meters) + 0.1, 0.01, 0)
            textNode.eulerAngles.x = -.pi / 2
            gridNode.addChildNode(textNode)
        }

        self.gridNode = gridNode
        scene.rootNode.addChildNode(gridNode)
    }

    private func createLine(from: SCNVector3, to: SCNVector3, color: NSColor) -> SCNNode {
        let vertices: [SCNVector3] = [from, to]
        let source = SCNGeometrySource(vertices: vertices)
        let indices: [Int32] = [0, 1]
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        let geometry = SCNGeometry(sources: [source], elements: [element])
        geometry.firstMaterial?.diffuse.contents = color
        geometry.firstMaterial?.isDoubleSided = true
        return SCNNode(geometry: geometry)
    }

    private func createRing(radius: Float, color: NSColor) -> SCNNode {
        let segments = 64
        var vertices: [SCNVector3] = []
        var indices: [Int32] = []

        for i in 0...segments {
            let angle = Float(i) / Float(segments) * 2 * .pi
            let x = cos(angle) * radius
            let z = sin(angle) * radius
            vertices.append(SCNVector3(x, 0, z))

            if i > 0 {
                indices.append(Int32(i - 1))
                indices.append(Int32(i))
            }
        }

        let source = SCNGeometrySource(vertices: vertices)
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        let geometry = SCNGeometry(sources: [source], elements: [element])
        geometry.firstMaterial?.diffuse.contents = color
        return SCNNode(geometry: geometry)
    }

    private func setupUserIndicator() {
        // Sphere for user position
        let sphere = SCNSphere(radius: 0.15)
        sphere.firstMaterial?.diffuse.contents = NSColor.cyan
        sphere.firstMaterial?.emission.contents = NSColor.cyan.withAlphaComponent(0.5)

        let userNode = SCNNode(geometry: sphere)
        userNode.position = SCNVector3(0, 0.15, 0)

        // Direction indicator (cone pointing forward)
        let cone = SCNCone(topRadius: 0, bottomRadius: 0.08, height: 0.3)
        cone.firstMaterial?.diffuse.contents = NSColor.cyan
        let coneNode = SCNNode(geometry: cone)
        coneNode.position = SCNVector3(0, 0, -0.25)
        coneNode.eulerAngles.x = .pi / 2
        userNode.addChildNode(coneNode)

        // Glow ring
        let ring = SCNTorus(ringRadius: 0.25, pipeRadius: 0.02)
        ring.firstMaterial?.diffuse.contents = NSColor.cyan.withAlphaComponent(0.3)
        let ringNode = SCNNode(geometry: ring)
        ringNode.position = SCNVector3(0, -0.14, 0)
        userNode.addChildNode(ringNode)

        self.userNode = userNode
        scene.rootNode.addChildNode(userNode)
    }

    func updatePointCloud(packet: StreamPacket?) {
        // Remove old point cloud
        pointCloudNode?.removeFromParentNode()

        guard let packet = packet, !packet.points.isEmpty else { return }

        // Build point cloud geometry
        var positions: [SCNVector3] = []
        var colors: [NSColor] = []

        let heading = packet.userHeading

        for point in packet.points {
            // Rotate points by heading so forward is always -Z
            let cosH = cos(-heading)
            let sinH = sin(-heading)
            let rotX = point.x * cosH - point.z * sinH
            let rotZ = point.x * sinH + point.z * cosH

            positions.append(SCNVector3(rotX, point.y, rotZ))

            // Color by category
            let color: NSColor
            switch point.c {
            case 0:  // floor
                color = NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1)
            case 1:  // obstacle
                color = NSColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 1)
            case 2:  // wall
                color = NSColor(red: 0.2, green: 0.4, blue: 1.0, alpha: 1)
            default:
                color = NSColor.gray
            }
            colors.append(color)
        }

        // Create geometry sources
        let positionSource = SCNGeometrySource(vertices: positions)

        // Color source
        var colorData = Data()
        for color in colors {
            var r = Float(color.redComponent)
            var g = Float(color.greenComponent)
            var b = Float(color.blueComponent)
            colorData.append(Data(bytes: &r, count: 4))
            colorData.append(Data(bytes: &g, count: 4))
            colorData.append(Data(bytes: &b, count: 4))
        }
        let colorSource = SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: colors.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: 4,
            dataOffset: 0,
            dataStride: 12
        )

        // Point element
        let indices = (0..<Int32(positions.count)).map { $0 }
        let element = SCNGeometryElement(indices: indices, primitiveType: .point)
        element.pointSize = 4
        element.minimumPointScreenSpaceRadius = 2
        element.maximumPointScreenSpaceRadius = 8

        let geometry = SCNGeometry(sources: [positionSource, colorSource], elements: [element])
        geometry.firstMaterial?.lightingModel = .constant
        geometry.firstMaterial?.isDoubleSided = true

        let node = SCNNode(geometry: geometry)
        pointCloudNode = node
        scene.rootNode.addChildNode(node)
    }
}

// MARK: - Network Receiver

class StreamReceiver: ObservableObject {
    private var listener: NWListener?
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "receiver")

    @Published var isConnected = false
    @Published var latestPacket: StreamPacket?
    @Published var fps: Int = 0
    @Published var localIP: String = "..."

    private var frameCount = 0
    private var lastFPSTime = Date()
    private let bufferLock = NSLock()
    private var byteBuffer: [UInt8] = []

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

    private func receiveLoop(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let error = error {
                print("[Mac] receive error: \(error)")
            }

            if let data = data, !data.isEmpty {
                self.bufferLock.lock()
                self.byteBuffer.append(contentsOf: data)
                self.bufferLock.unlock()
                self.processPackets()
            }

            if !isComplete && error == nil {
                self.receiveLoop(connection)
            }
        }
    }

    private func processPackets() {
        bufferLock.lock()

        while byteBuffer.count >= 4 {
            let length = (UInt32(byteBuffer[0]) << 24) |
                        (UInt32(byteBuffer[1]) << 16) |
                        (UInt32(byteBuffer[2]) << 8) |
                         UInt32(byteBuffer[3])

            let packetSize = Int(length)
            let totalNeeded = 4 + packetSize

            guard byteBuffer.count >= totalNeeded else { break }

            let packetBytes = Array(byteBuffer[4..<totalNeeded])
            byteBuffer.removeFirst(totalNeeded)

            bufferLock.unlock()

            let packetData = Data(packetBytes)
            if let packet = try? JSONDecoder().decode(StreamPacket.self, from: packetData) {
                DispatchQueue.main.async { [weak self] in
                    self?.latestPacket = packet
                    self?.updateFPS()
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
}

// MARK: - Packet Structure (must match iPhone)

struct Point3D: Codable {
    var x: Float
    var y: Float
    var z: Float
    var c: UInt8
}

struct StreamPacket: Codable {
    var timestamp: Double = 0
    var userPosition: [Float] = [0, 0, 0]
    var userHeading: Float = 0
    var nearestObstacle: Float = .infinity
    var gridSize: Int = 40
    var cellSize: Float = 0.2
    var grid: [Int8] = []
    var points: [Point3D] = []
}
