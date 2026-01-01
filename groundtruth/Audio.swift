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
    private var stepBuffer: AVAudioPCMBuffer?    // step warning
    private var curbBuffer: AVAudioPCMBuffer?    // curb warning
    private var dangerBuffer: AVAudioPCMBuffer?  // danger warning
    
    // format for buffers (must match player connection)
    private var bufferFormat: AVAudioFormat?
    
    // state
    private var isRunning = false
    private var lastBeepTime: Double = 0
    private var lastElevationTime: Double = 0
    private let minBeepInterval: Double = 0.15
    private let minElevationInterval: Double = 0.5  // elevation warnings less frequent
    
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
        
        // step sound - rising tone (indicates step up/down)
        stepBuffer = generateChirpBuffer(startFreq: 600, endFreq: 900, duration: 0.15, format: format)
        
        // curb sound - lower, longer (more warning)
        curbBuffer = generateSineBuffer(frequency: 400, duration: 0.25, format: format)
        
        // danger sound - rapid low beeps
        dangerBuffer = generateDangerBuffer(frequency: 300, duration: 0.4, format: format)
        
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
    
    // Chirp - frequency sweep for step indication
    private func generateChirpBuffer(
        startFreq: Double,
        endFreq: Double,
        duration: Double,
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        
        buffer.frameLength = frameCount
        guard let data = buffer.floatChannelData?[0] else { return nil }
        
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            let progress = t / duration
            let frequency = startFreq + (endFreq - startFreq) * progress
            
            let fadeIn = min(t / 0.005, 1.0)
            let fadeOut = min((duration - t) / 0.01, 1.0)
            let envelope = fadeIn * fadeOut
            
            data[i] = Float(sin(2.0 * .pi * frequency * t) * envelope * 0.5)
        }
        
        return buffer
    }
    
    // Danger - rapid pulses
    private func generateDangerBuffer(
        frequency: Double,
        duration: Double,
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        
        buffer.frameLength = frameCount
        guard let data = buffer.floatChannelData?[0] else { return nil }
        
        let pulseRate = 8.0 // 8 pulses per second
        
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            let pulse = sin(2.0 * .pi * pulseRate * t) > 0 ? 1.0 : 0.0
            data[i] = Float(sin(2.0 * .pi * frequency * t) * pulse * 0.7)
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
    
    // New interface - called from processing queue
    func update(
        nearestObstacle: Float,
        userHeading: Float,
        elevationWarning: ElevationChange?
    ) {
        guard isRunning else { return }
        
        let now = CACurrentMediaTime()
        
        // Handle elevation warnings (higher priority)
        if let warning = elevationWarning, warning.distance < 3.0 {
            if now - lastElevationTime >= minElevationInterval {
                lastElevationTime = now
                playElevationWarning(warning)
                return  // Don't play obstacle beep if we just played elevation warning
            }
        }
        
        // Handle obstacle beeps
        guard nearestObstacle < 5.0 else { return }
        
        // beep rate based on distance (closer = faster)
        let interval: Double
        if nearestObstacle < 0.5 {
            interval = 0.12  // very fast - danger!
        } else if nearestObstacle < 1.0 {
            interval = 0.2
        } else if nearestObstacle < 2.0 {
            interval = 0.35
        } else if nearestObstacle < 3.0 {
            interval = 0.5
        } else {
            interval = 0.8
        }
        
        guard now - lastBeepTime >= interval else { return }
        lastBeepTime = now
        
        // Position sound ahead (obstacle is in front)
        beepPlayer?.position = AVAudio3DPoint(x: 0, y: 0, z: -2)  // in front
        
        // volume based on distance (closer = louder)
        let volume = max(0.2, min(1.0, 1.5 / nearestObstacle))
        beepPlayer?.volume = volume
        
        playBeep()
    }
    
    private func playElevationWarning(_ warning: ElevationChange) {
        guard let player = beepPlayer else { return }
        
        // Position sound based on warning angle
        let x = sin(warning.angle) * 2.0
        let z = -cos(warning.angle) * 2.0  // negative z = in front
        player.position = AVAudio3DPoint(x: Float(x), y: 0, z: Float(z))
        
        // volume based on distance
        let volume = max(0.3, min(1.0, 2.0 / warning.distance))
        player.volume = volume
        
        // Select appropriate buffer
        let buffer: AVAudioPCMBuffer?
        switch warning.type {
        case .stepUp, .stepDown:
            buffer = stepBuffer
        case .curbUp, .curbDown:
            buffer = curbBuffer
        case .dropoff:
            buffer = dangerBuffer
        case .stairs:
            buffer = stepBuffer
        default:
            buffer = beepBuffer
        }
        
        guard let buf = buffer else { return }
        
        DispatchQueue.main.async {
            player.stop()
            player.scheduleBuffer(buf, at: nil, options: [], completionHandler: nil)
            player.play()
        }
    }
    
    private func playBeep() {
        guard let player = beepPlayer, let buf = beepBuffer else { return }
        
        DispatchQueue.main.async {
            player.stop()
            player.scheduleBuffer(buf, at: nil, options: [], completionHandler: nil)
            player.play()
        }
    }
}
