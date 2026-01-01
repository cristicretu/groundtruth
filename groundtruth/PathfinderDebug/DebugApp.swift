// DebugApp.swift
// Point cloud visualizer - clean and simple
import SwiftUI
import SceneKit
import Network

@main
struct PathfinderDebugApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 600)
        }
    }
}

struct ContentView: View {
    @StateObject private var stream = StreamReceiver()

    var body: some View {
        HStack(spacing: 0) {
            // 3D view
            SceneKitView(mesh: stream.mesh, heading: stream.heading)

            // Stats
            VStack(alignment: .leading, spacing: 12) {
                Text("PATHFINDER")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)

                Circle()
                    .fill(stream.connected ? Color.green : Color.red)
                    .frame(width: 10, height: 10)

                if let m = stream.mesh {
                    Text("Verts: \(m.vertices.count / 3)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.cyan)
                    Text("Tris: \(m.indices.count / 3)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.cyan)
                }

                Text("FPS: \(stream.fps)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.cyan)

                Text(String(format: "%.0f°", stream.heading * 180 / .pi))
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)

                Spacer()

                Text(stream.localIP)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.gray)
            }
            .padding()
            .frame(width: 150)
            .background(Color.black)
        }
        .background(Color.black)
    }
}

// MARK: - SceneKit View

struct SceneKitView: NSViewRepresentable {
    let mesh: MeshData?
    let heading: Float

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.scene
        view.backgroundColor = .black
        view.allowsCameraControl = true
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        context.coordinator.update(mesh: mesh, heading: heading)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        let scene = SCNScene()
        private var meshNode: SCNNode?
        private var userNode: SCNNode?

        init() {
            // Camera - higher up for better view
            let cam = SCNNode()
            cam.camera = SCNCamera()
            cam.position = SCNVector3(0, 4, 6)
            cam.look(at: SCNVector3(0, 0, 0))
            scene.rootNode.addChildNode(cam)

            // Ambient light
            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 500
            scene.rootNode.addChildNode(ambient)

            // Grid
            for i in -5...5 {
                let v = makeLine(SCNVector3(Float(i), 0, -5), SCNVector3(Float(i), 0, 5))
                let h = makeLine(SCNVector3(-5, 0, Float(i)), SCNVector3(5, 0, Float(i)))
                scene.rootNode.addChildNode(v)
                scene.rootNode.addChildNode(h)
            }

            // User marker
            let sphere = SCNSphere(radius: 0.1)
            sphere.firstMaterial?.diffuse.contents = NSColor.cyan
            sphere.firstMaterial?.emission.contents = NSColor.cyan
            userNode = SCNNode(geometry: sphere)
            userNode?.position = SCNVector3(0, 0.1, 0)
            scene.rootNode.addChildNode(userNode!)

            // Arrow
            let cone = SCNCone(topRadius: 0, bottomRadius: 0.05, height: 0.2)
            cone.firstMaterial?.diffuse.contents = NSColor.cyan
            let arrow = SCNNode(geometry: cone)
            arrow.eulerAngles.x = -.pi/2
            arrow.position = SCNVector3(0, 0, -0.15)
            userNode?.addChildNode(arrow)
        }

        func makeLine(_ a: SCNVector3, _ b: SCNVector3) -> SCNNode {
            let src = SCNGeometrySource(vertices: [a, b])
            let idx = SCNGeometryElement(indices: [Int32(0), Int32(1)], primitiveType: .line)
            let geo = SCNGeometry(sources: [src], elements: [idx])
            geo.firstMaterial?.diffuse.contents = NSColor(white: 0.2, alpha: 1)
            return SCNNode(geometry: geo)
        }

        func colorForClass(_ c: UInt8) -> (Float, Float, Float) {
            switch c {
            case 0: return (0.3, 0.3, 0.35)   // floor - gray
            case 1: return (1.0, 0.3, 0.3)    // obstacle - red
            case 2: return (0.4, 0.6, 1.0)    // wall - blue
            case 3: return (0.25, 0.25, 0.3)  // ceiling - dark
            case 4: return (1.0, 0.7, 0.2)    // furniture - orange
            case 5: return (0.3, 0.8, 0.4)    // door - green
            case 6: return (0.6, 0.8, 1.0)    // window - light blue
            default: return (0.5, 0.5, 0.5)
            }
        }

        func update(mesh: MeshData?, heading: Float) {
            userNode?.eulerAngles.y = CGFloat(-heading)

            guard let m = mesh, !m.vertices.isEmpty, !m.indices.isEmpty else { return }

            meshNode?.removeFromParentNode()

            let vertCount = m.vertices.count / 3

            // Flip Z for SceneKit coords
            var verts = m.vertices
            for i in stride(from: 2, to: verts.count, by: 3) {
                verts[i] = -verts[i]
            }

            // Build colors from classification
            var cols: [Float] = []
            cols.reserveCapacity(vertCount * 3)
            for i in 0..<vertCount {
                let c = i < m.classes.count ? m.classes[i] : 1
                let (r, g, b) = colorForClass(c)
                cols.append(contentsOf: [r, g, b])
            }

            let vertData = verts.withUnsafeBytes { Data($0) }
            let colData = cols.withUnsafeBytes { Data($0) }
            let idxData = m.indices.withUnsafeBytes { Data($0) }

            let vertSrc = SCNGeometrySource(data: vertData, semantic: .vertex, vectorCount: vertCount,
                                            usesFloatComponents: true, componentsPerVector: 3,
                                            bytesPerComponent: 4, dataOffset: 0, dataStride: 12)
            let colSrc = SCNGeometrySource(data: colData, semantic: .color, vectorCount: vertCount,
                                           usesFloatComponents: true, componentsPerVector: 3,
                                           bytesPerComponent: 4, dataOffset: 0, dataStride: 12)

            let triCount = m.indices.count / 3
            let elem = SCNGeometryElement(data: idxData, primitiveType: .triangles,
                                          primitiveCount: triCount, bytesPerIndex: 4)

            let geo = SCNGeometry(sources: [vertSrc, colSrc], elements: [elem])
            geo.firstMaterial?.isDoubleSided = true
            geo.firstMaterial?.lightingModel = .constant

            let node = SCNNode(geometry: geo)
            meshNode = node
            scene.rootNode.addChildNode(node)
        }
    }
}

// MARK: - Network

class StreamReceiver: ObservableObject {
    @Published var mesh: MeshData?
    @Published var heading: Float = 0
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
                if String(cString: iface.ifa_name) == "en0" {
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
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, err in
            if let err = err {
                print("[recv] error: \(err)")
                return
            }
            guard let self = self, let data = data else {
                print("[recv] no data")
                return
            }
            print("[recv] got \(data.count) bytes, buf now \(self.buf.count + data.count)")
            self.buf.append(contentsOf: data)
            self.process()
            if !done { self.recv(c) }
        }
    }

    func process() {
        while buf.count >= 4 {
            let len = Int(buf[0]) << 24 | Int(buf[1]) << 16 | Int(buf[2]) << 8 | Int(buf[3])
            guard buf.count >= 4 + len else { break }
            let pkt = Data(buf[4..<4+len])
            buf.removeFirst(4 + len)

            do {
                let p = try JSONDecoder().decode(Packet.self, from: pkt)
                if let m = p.mesh {
                    print("[recv] mesh: \(m.vertices.count/3) verts, \(m.indices.count/3) tris")
                }
                DispatchQueue.main.async {
                    self.mesh = p.mesh
                    self.heading = p.userHeading
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

// MARK: - Data

struct Point3D: Codable {
    var x: Float
    var y: Float
    var z: Float
    var c: UInt8
}

struct MeshData: Codable {
    var vertices: [Float]   // x,y,z,x,y,z,...
    var indices: [UInt32]   // triangle indices
    var classes: [UInt8]    // per-vertex classification
}

struct Packet: Codable {
    var userHeading: Float = 0
    var points: [Point3D] = []
    var mesh: MeshData?
}
