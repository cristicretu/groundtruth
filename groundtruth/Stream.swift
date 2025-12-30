// Stream.swift
// Debug streaming to Mac - send depth + world model over local network
import Foundation
import Network
import ARKit

final class DebugStream {
    private var connection: NWConnection?
    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "stream", qos: .utility)
    
    // streaming state
    private var isConnected = false
    private var frameCount = 0
    private let sendEveryNFrames = 6  // ~10fps streaming to reduce lag
    
    // callbacks
    var onConnected: (() -> Void)?
    var onDisconnected: (() -> Void)?
    
    init() {}
    
    // Browse for Mac debug receiver
    func startBrowsing() {
        print("[Stream] startBrowsing")
        let params = NWParameters()
        params.includePeerToPeer = true
        
        browser = NWBrowser(for: .bonjour(type: "_pathfinder._tcp", domain: nil), using: params)
        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            guard let self = self else { return }
            // Only connect if not already connected
            guard !self.isConnected && self.connection == nil else {
                print("[Stream] already connected, ignoring browse result")
                return
            }
            // connect to first found service
            if let endpoint = results.first?.endpoint {
                print("[Stream] found service: \(endpoint)")
                self.connect(to: endpoint)
            }
        }
        browser?.start(queue: queue)
    }
    
    func stopBrowsing() {
        browser?.cancel()
        browser = nil
    }
    
    // Connect directly to IP
    func connect(to host: String, port: UInt16 = 8765) {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )
        connect(to: endpoint)
    }
    
    private func connect(to endpoint: NWEndpoint) {
        print("[Stream] connecting to: \(endpoint)")
        
        // Cancel any existing connection first
        connection?.cancel()
        connection = nil
        isConnected = false
        
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        
        connection = NWConnection(to: endpoint, using: params)
        connection?.stateUpdateHandler = { [weak self] state in
            print("[Stream] connection state: \(state)")
            switch state {
            case .ready:
                print("[Stream] connected!")
                self?.isConnected = true
                self?.onConnected?()
            case .failed(let error):
                print("[Stream] failed: \(error)")
                self?.isConnected = false
                self?.connection = nil
                self?.onDisconnected?()
            case .cancelled:
                print("[Stream] cancelled")
                self?.isConnected = false
                self?.connection = nil
                self?.onDisconnected?()
            default:
                break
            }
        }
        connection?.start(queue: queue)
    }
    
    func disconnect() {
        connection?.cancel()
        connection = nil
        isConnected = false
    }
    
    // Send frame data to Mac
    func send(frame: ARFrame, world: WorldModel, grid: OccupancyGrid, points: [Point3D] = []) {
        guard isConnected else { return }

        // throttle
        frameCount += 1
        guard frameCount % sendEveryNFrames == 0 else { return }

        // build packet
        var packet = StreamPacket()
        packet.timestamp = frame.timestamp
        packet.userPosition = [world.userPosition.x, world.userPosition.y, world.userPosition.z]
        packet.userHeading = world.userHeading
        packet.nearestObstacle = world.nearestObstacle
        packet.gridSize = grid.gridSize
        packet.cellSize = grid.cellSize
        packet.points = points
        
        // Flatten grid to 1D array - encode height as Int8 (cm)
        var flatGrid: [Int8] = []
        flatGrid.reserveCapacity(grid.gridSize * grid.gridSize)
        
        let userY = world.userPosition.y
        for z in 0..<grid.gridSize {
            for x in 0..<grid.gridSize {
                let cell = grid.cells[x][z]
                if cell.isValid {
                    // Height above floor in cm, clamped to Int8 range
                    let heightCm = Int(cell.height * 100)
                    flatGrid.append(Int8(clamping: min(127, max(-128, heightCm))))
                } else {
                    flatGrid.append(-128)  // Unknown
                }
            }
        }
        packet.grid = flatGrid
        
        // serialize and send
        if let data = try? JSONEncoder().encode(packet) {
            // send length prefix + data
            var length = UInt32(data.count).bigEndian
            let lengthData = Data(bytes: &length, count: 4)
            
            let packetNum = frameCount / sendEveryNFrames
            if packetNum % 20 == 0 {
                print("[Stream] sending packet #\(packetNum), size: \(data.count) bytes")
            }
            
            connection?.send(content: lengthData + data, completion: .contentProcessed { [weak self] error in
                if let error = error {
                    print("[Stream] send error: \(error)")
                    self?.isConnected = false
                }
            })
        } else {
            print("[Stream] failed to encode packet")
        }
    }
    
    private func compressDepth(_ buffer: CVPixelBuffer) -> Data? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let ptr = CVPixelBufferGetBaseAddress(buffer)!
        
        // Send full resolution - depth maps are typically 256x192, small enough
        let srcPtr = ptr.assumingMemoryBound(to: Float32.self)
        let count = width * height
        
        // Copy to array
        var depthValues = [Float32](repeating: 0, count: count)
        for i in 0..<count {
            depthValues[i] = srcPtr[i]
        }
        
        return depthValues.withUnsafeBytes { Data($0) }
    }
}

// Packet structure for streaming (matches Mac side)
struct StreamPacket: Codable {
    var timestamp: Double = 0
    var userPosition: [Float] = [0, 0, 0]
    var userHeading: Float = 0
    var nearestObstacle: Float = .infinity

    // Occupancy grid - clean 2D top-down map
    var gridSize: Int = 40        // 40x40 grid
    var cellSize: Float = 0.2     // 20cm per cell
    var grid: [Int8] = []         // flattened grid: height in cm per cell (0=floor, >15=obstacle)

    // 3D point cloud for visualization
    var points: [Point3D] = []
}
