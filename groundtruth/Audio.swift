// Audio.swift
// Spatial audio feedback - sounds come FROM obstacles
import AVFoundation
import simd

final class SpatialAudio {
    private let engine = AVAudioEngine()
    private let environment = AVAudioEnvironmentNode()
    
    // obstacle beep (triggered)
    private var beepPlayer: AVAudioPlayerNode?
    private var beepBuffer: AVAudioPCMBuffer?
    private var curbBuffer: AVAudioPCMBuffer?  // different sound for curbs
    
    // format for buffers (must match player connection)
    private var bufferFormat: AVAudioFormat?
    
    // state
    private var isRunning = false
    private var lastBeepTime: Double = 0
    private let minBeepInterval: Double = 0.15
    
    init() {
        setupAudioSession()
        setupEngine()
    }
    
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("[Audio] session error: \(error)")
        }
    }
    
    private func setupEngine() {
        // environment node for 3D positioning
        engine.attach(environment)
        
        // connect environment to main mixer
        let outputFormat = engine.outputNode.inputFormat(forBus: 0)
        engine.connect(environment, to: engine.mainMixerNode, format: outputFormat)
        
        // set listener at origin facing forward
        environment.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
        environment.listenerAngularOrientation = AVAudio3DAngularOrientation(yaw: 0, pitch: 0, roll: 0)
        
        // beep player - use MONO format for 3D spatialization
        beepPlayer = AVAudioPlayerNode()
        engine.attach(beepPlayer!)
        
        // Create mono format for spatial audio (environment node needs mono input for 3D positioning)
        bufferFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)
        engine.connect(beepPlayer!, to: environment, format: bufferFormat)
        
        // generate tones after format is set
        generateTones()
        
        print("[Audio] engine setup complete")
    }
    
    private func generateTones() {
        guard let format = bufferFormat else {
            print("[Audio] no buffer format")
            return
        }
        
        // beep - 1200Hz short burst for obstacles
        beepBuffer = generateSineBuffer(frequency: 1200, duration: 0.08, format: format)
        
        // curb sound - lower pitch, longer
        curbBuffer = generateSineBuffer(frequency: 600, duration: 0.15, format: format)
        
        print("[Audio] tones generated")
    }
    
    private func generateSineBuffer(
        frequency: Double,
        duration: Double,
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            print("[Audio] failed to create buffer")
            return nil
        }
        
        buffer.frameLength = frameCount
        guard let data = buffer.floatChannelData?[0] else { return nil }
        
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            // sine wave with fade in/out envelope
            let fadeIn = min(t / 0.005, 1.0)
            let fadeOut = min((duration - t) / 0.005, 1.0)
            let envelope = fadeIn * fadeOut
            data[i] = Float(sin(2.0 * .pi * frequency * t) * envelope * 0.6)
        }
        
        return buffer
    }
    
    func start() {
        guard !isRunning else { return }
        do {
            try engine.start()
            isRunning = true
            print("[Audio] engine started")
        } catch {
            print("[Audio] engine start error: \(error)")
        }
    }
    
    func stop() {
        beepPlayer?.stop()
        engine.stop()
        isRunning = false
        print("[Audio] engine stopped")
    }
    
    // Update based on world state - called from processing queue
    func update(world: WorldModel) {
        guard isRunning else { return }
        guard world.nearestObstacle < 5.0 else { return }  // only beep if something within 5m
        
        let now = CACurrentMediaTime()
        
        // find nearest obstacle for positioning
        guard let nearest = world.obstacles.min(by: { $0.distance < $1.distance }) else { return }
        
        let dist = nearest.distance
        
        // beep rate based on distance (closer = faster)
        let interval: Double
        if dist < 0.5 {
            interval = 0.12  // very fast - danger!
        } else if dist < 1.0 {
            interval = 0.2
        } else if dist < 2.0 {
            interval = 0.35
        } else if dist < 3.0 {
            interval = 0.5
        } else {
            interval = 0.8
        }
        
        // play beep if enough time has passed
        guard now - lastBeepTime >= interval else { return }
        lastBeepTime = now
        
        // position sound in 3D space
        // angle: 0 = ahead, positive = right, negative = left
        let x = sin(nearest.angle) * 2.0
        let z = -cos(nearest.angle) * 2.0  // negative z = in front
        
        beepPlayer?.position = AVAudio3DPoint(x: Float(x), y: 0, z: Float(z))
        
        // volume based on distance (closer = louder)
        let volume = max(0.2, min(1.0, 1.5 / dist))
        beepPlayer?.volume = volume
        
        // play appropriate sound
        playBeep(isCurb: nearest.isCurb)
    }
    
    private func playBeep(isCurb: Bool) {
        guard let player = beepPlayer else { return }
        let buffer = isCurb ? curbBuffer : beepBuffer
        guard let buf = buffer else { return }
        
        // schedule and play on main thread to avoid threading issues
        DispatchQueue.main.async {
            player.stop()
            player.scheduleBuffer(buf, at: nil, options: [], completionHandler: nil)
            player.play()
        }
    }
}
