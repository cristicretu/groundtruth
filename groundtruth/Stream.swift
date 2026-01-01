// Stream.swift
// Debug streaming to Mac - send occupancy grid + elevation data
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
    private let sendEveryNFrames = 3  // ~20fps streaming
    
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
    
    // Send frame data to Mac - new occupancy grid format
    func send(
        timestamp: Double,
        userPosition: simd_float3,
        userHeading: Float,
        grid: OccupancyGrid,
        elevationChanges: [ElevationChange] = [],
        nearestObstacle: Float = .infinity
    ) {
        guard isConnected else { return }
        
        // throttle
        frameCount += 1
        guard frameCount % sendEveryNFrames == 0 else { return }
        
        // build packet
        var packet = StreamPacket()
        packet.timestamp = timestamp
        packet.userPosition = [userPosition.x, userPosition.y, userPosition.z]
        packet.userHeading = userHeading
        packet.nearestObstacle = nearestObstacle
        packet.floorHeight = grid.floorHeight
        
        // Grid metadata
        packet.gridSize = grid.gridSize
        packet.cellSize = grid.cellSize
        
        // Flatten grid - state and elevation for each cell
        var states: [UInt8] = []
        var elevations: [Int8] = []
        states.reserveCapacity(grid.gridSize * grid.gridSize)
        elevations.reserveCapacity(grid.gridSize * grid.gridSize)
        
        for z in 0..<grid.gridSize {
            for x in 0..<grid.gridSize {
                let cell = grid.cells[x][z]
                states.append(cell.state.rawValue)
                
                // Elevation as cm, clamped to Int8 range
                let elevCm = Int(cell.elevation * 100)
                elevations.append(Int8(clamping: max(-128, min(127, elevCm))))
            }
        }
        
        packet.cellStates = states
        packet.cellElevations = elevations
        
        // Stats
        packet.validCells = grid.validCellCount
        packet.obstacleCells = grid.obstacleCellCount
        packet.stepCells = grid.stepCellCount
        
        // Elevation changes (most important ones)
        packet.elevationChanges = Array(elevationChanges.prefix(10)).map { change in
            StreamElevationChange(
                type: change.type.rawValue,
                posX: change.position.x,
                posZ: change.position.y,
                distance: change.distance,
                angle: change.angle,
                heightChange: change.heightChange
            )
        }
        
        // serialize and send
        if let data = try? JSONEncoder().encode(packet) {
            // send length prefix + data
            var length = UInt32(data.count).bigEndian
            let lengthData = Data(bytes: &length, count: 4)
            
            let packetNum = frameCount / sendEveryNFrames
            if packetNum % 30 == 0 {
                print("[Stream] packet #\(packetNum): \(data.count) bytes, valid:\(grid.validCellCount) obs:\(grid.obstacleCellCount) step:\(grid.stepCellCount)")
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
}

// Elevation change for streaming
struct StreamElevationChange: Codable {
    var type: UInt8
    var posX: Float
    var posZ: Float
    var distance: Float
    var angle: Float
    var heightChange: Float
}

// Packet structure for streaming (matches Mac side)
struct StreamPacket: Codable {
    var timestamp: Double = 0
    var userPosition: [Float] = [0, 0, 0]
    var userHeading: Float = 0
    var nearestObstacle: Float = .infinity
    var floorHeight: Float = 0
    
    // Grid metadata
    var gridSize: Int = 200
    var cellSize: Float = 0.1
    
    // Grid data (flattened)
    var cellStates: [UInt8] = []      // CellState raw values
    var cellElevations: [Int8] = []   // Elevation in cm
    
    // Stats
    var validCells: Int = 0
    var obstacleCells: Int = 0
    var stepCells: Int = 0
    
    // Detected elevation changes
    var elevationChanges: [StreamElevationChange] = []
}
