// Stream.swift
// Debug streaming to Mac - send occupancy grid + navigation data
import Foundation
import Network
import simd

final class DebugStream {
    private var connection: NWConnection?
    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "stream", qos: .utility)

    // streaming state
    private var isConnected = false
    private var frameCount = 0

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
            guard !self.isConnected && self.connection == nil else {
                print("[Stream] already connected, ignoring browse result")
                return
            }
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
    func connect(to host: String, port: UInt16 = StreamConfig.port) {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )
        connect(to: endpoint)
    }

    private func connect(to endpoint: NWEndpoint) {
        print("[Stream] connecting to: \(endpoint)")

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
    func send(
        timestamp: Double,
        userPosition: simd_float3,
        userHeading: Float,
        grid: OccupancyGrid,
        navigationOutput: NavigationOutput,
        nearestObstacle: Float = .infinity,
        detectedObjects: [StreamDetectedObject] = []
    ) {
        guard isConnected else { return }

        // throttle to ~20fps
        frameCount += 1
        guard frameCount % StreamConfig.sendEveryNFrames == 0 else { return }

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

        // Flatten grid
        var states: [UInt8] = []
        var elevations: [Int8] = []
        states.reserveCapacity(grid.gridSize * grid.gridSize)
        elevations.reserveCapacity(grid.gridSize * grid.gridSize)

        for z in 0..<grid.gridSize {
            for x in 0..<grid.gridSize {
                let cell = grid.cells[x][z]
                states.append(cell.state.rawValue)
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

        // Navigation output (new fields)
        packet.navigationHeading = navigationOutput.suggestedHeading
        packet.groundConfidence = navigationOutput.groundConfidence
        packet.obstacleDistance = navigationOutput.nearestObstacleDistance
        if let disc = navigationOutput.discontinuityAhead {
            packet.discontinuityCount = 1
            packet.nearestDiscontinuityDistance = disc.distance
        }

        // Detected objects (backward compat)
        packet.detectedObjects = detectedObjects

        // serialize and send
        if let data = try? JSONEncoder().encode(packet) {
            var length = UInt32(data.count).bigEndian
            let lengthData = Data(bytes: &length, count: 4)

            let packetNum = frameCount / StreamConfig.sendEveryNFrames
            if packetNum % 30 == 0 {
                print("[Stream] packet #\(packetNum): \(data.count) bytes, valid:\(grid.validCellCount) obs:\(grid.obstacleCellCount)")
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

// Elevation change for streaming (backward compat)
struct StreamElevationChange: Codable {
    var type: UInt8
    var posX: Float
    var posZ: Float
    var distance: Float
    var angle: Float
    var heightChange: Float
}

struct StreamDetectedObject: Codable {
    var type: String
    var confidence: Float
    var posX: Float
    var posZ: Float
    var distance: Float
    var bearing: Float
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
    var cellStates: [UInt8] = []
    var cellElevations: [Int8] = []

    // Stats
    var validCells: Int = 0
    var obstacleCells: Int = 0
    var stepCells: Int = 0

    // Detected elevation changes (backward compat)
    var elevationChanges: [StreamElevationChange] = []

    // Fused YOLO + depth detections (backward compat)
    var detectedObjects: [StreamDetectedObject] = []

    // Navigation pipeline (new)
    var navigationHeading: Float?
    var groundConfidence: Float?
    var discontinuityCount: Int?
    var nearestDiscontinuityDistance: Float?
    var obstacleDistance: Float?
}
