import Foundation
import AVFoundation

enum SoundName: String, CaseIterable {
    case click
    case spawn
    case birth
    case death
    case water
    case rock
    case plant
    case rain
    case drought
    case meteor
    case success
    case start
}

/// Bruitages 100 % synthétisés : aucun fichier audio dans le bundle.
final class SoundEngine {
    static let shared = SoundEngine()

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
    private var players: [AVAudioPlayerNode] = []
    private var ambience: AVAudioPlayerNode?
    private var buffers: [SoundName: AVAudioPCMBuffer] = [:]
    private var nextPlayer = 0
    private var started = false

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "biome.sound") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "biome.sound") }
    }

    private init() {}

    func start() {
        guard !started else { return }
        guard let format else { return }
        started = true

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: [])
        } catch {
            print("[Biome] audio session:", error.localizedDescription)
        }

        for _ in 0..<8 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }

        buildBuffers()
        engine.mainMixerNode.outputVolume = 0.75
        do {
            try engine.start()
        } catch {
            print("[Biome] engine:", error.localizedDescription)
            return
        }
        for player in players { player.play() }
        startAmbience()
    }

    func play(_ name: SoundName) {
        guard isEnabled, started, let buffer = buffers[name], !players.isEmpty else { return }
        let player = players[nextPlayer % players.count]
        nextPlayer += 1
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        player.play()
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            start()
        } else {
            ambience?.stop()
        }
    }

    // MARK: - Synthèse

    private func buildBuffers() {
        buffers[.click] = tone(duration: 0.07, from: 900, to: 620, volume: 0.18)
        buffers[.spawn] = tone(duration: 0.30, from: 430, to: 720, volume: 0.26, shimmer: true)
        buffers[.birth] = tone(duration: 0.16, from: 880, to: 1320, volume: 0.16)
        buffers[.death] = tone(duration: 0.35, from: 190, to: 90, volume: 0.28, noise: 0.35)
        buffers[.water] = tone(duration: 0.28, from: 520, to: 260, volume: 0.22, noise: 0.75)
        buffers[.rock] = tone(duration: 0.18, from: 140, to: 70, volume: 0.26, noise: 0.65)
        buffers[.plant] = tone(duration: 0.22, from: 620, to: 780, volume: 0.18)
        buffers[.rain] = tone(duration: 0.90, from: 800, to: 300, volume: 0.20, noise: 0.95)
        buffers[.drought] = tone(duration: 0.80, from: 340, to: 110, volume: 0.24, noise: 0.25)
        buffers[.meteor] = tone(duration: 1.10, from: 120, to: 40, volume: 0.45, noise: 0.85)
        buffers[.success] = arpeggio([523.25, 659.25, 783.99, 1046.5], spacing: 0.09, volume: 0.20)
        buffers[.start] = arpeggio([261.6, 392.0, 523.25, 659.25], spacing: 0.12, volume: 0.18)
    }

    private func tone(
        duration: Float,
        from startFrequency: Float,
        to endFrequency: Float,
        volume: Float,
        noise: Float = 0,
        shimmer: Bool = false
    ) -> AVAudioPCMBuffer? {
        guard let format else { return nil }
        let sampleRate = Float(format.sampleRate)
        let frames = AVAudioFrameCount(duration * sampleRate)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        guard let channel = buffer.floatChannelData?[0] else { return nil }

        var rng = SplitMix64(seed: 0xB10E_5EED)
        var phase: Float = 0
        for i in 0..<Int(frames) {
            let t = Float(i) / sampleRate
            let progress = t / duration
            let frequency = startFrequency + (endFrequency - startFrequency) * progress
            phase += 2 * Float.pi * frequency / sampleRate
            let envelope = expf(-3.2 * progress) * (1 - progress * 0.2)
            var sample = sinf(phase)
            if shimmer {
                sample += 0.4 * sinf(phase * 2.01)
                sample += 0.2 * sinf(phase * 3.02)
            }
            if noise > 0 {
                sample = sample * (1 - noise) + rng.range(-1, 1) * noise
            }
            channel[i] = sample * envelope * volume
        }
        return buffer
    }

    private func arpeggio(_ frequencies: [Float], spacing: Float, volume: Float) -> AVAudioPCMBuffer? {
        guard let format else { return nil }
        let sampleRate = Float(format.sampleRate)
        let noteDuration = spacing * 1.8
        let duration = noteDuration + spacing * Float(max(0, frequencies.count - 1))
        let frames = AVAudioFrameCount(duration * sampleRate)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        guard let channel = buffer.floatChannelData?[0] else { return nil }

        for i in 0..<Int(frames) {
            channel[i] = 0
        }
        for (noteIndex, frequency) in frequencies.enumerated() {
            let startTime = spacing * Float(noteIndex)
            let startFrame = Int(startTime * sampleRate)
            var phase: Float = 0
            var i = 0
            let noteFrames = Int(noteDuration * sampleRate)
            while i < noteFrames {
                let frame = startFrame + i
                if frame >= Int(frames) { break }
                let t = Float(i) / sampleRate
                let progress = t / noteDuration
                phase += 2 * Float.pi * frequency / sampleRate
                let envelope = expf(-4.5 * progress)
                channel[frame] += sinf(phase) * envelope * volume
                i += 1
            }
        }
        return buffer
    }

    private func startAmbience() {
        guard isEnabled, let format else { return }
        let sampleRate = Float(format.sampleRate)
        let duration: Float = 8
        let frames = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        buffer.frameLength = frames
        guard let channel = buffer.floatChannelData?[0] else { return }

        var rng = SplitMix64(seed: 0xA1B2_C3D4)
        var lowPass: Float = 0
        for i in 0..<Int(frames) {
            let value = rng.range(-1, 1)
            lowPass += (value - lowPass) * 0.012
            let fade = min(1, Float(i) / 4410) * min(1, Float(Int(frames) - i) / 4410)
            channel[i] = lowPass * 0.16 * fade
        }

        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        player.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        player.volume = 0.5
        player.play()
        ambience = player
    }
}
