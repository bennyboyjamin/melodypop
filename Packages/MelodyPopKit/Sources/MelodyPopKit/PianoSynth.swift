import Foundation

public struct PianoSample: Sendable {
    public enum Layer: String, Sendable, CaseIterable { case soft, loud }
    public let rootMIDI: Int
    public let layer: Layer
    public let frames: [Float]
    public let sampleRate: Double

    public init(rootMIDI: Int, layer: Layer, frames: [Float], sampleRate: Double) {
        self.rootMIDI = rootMIDI
        self.layer = layer
        self.frames = frames
        self.sampleRate = sampleRate
    }
}

/// Multisampled piano: each key plays the nearest recorded root, pitch-shifted by resampling.
public struct SampleBank: Sendable {
    public let samples: [PianoSample]
    /// Velocity at or above which the loud layer is used.
    public var layerSplit: Float = 0.55

    public init(samples: [PianoSample]) {
        self.samples = samples
    }

    public var isEmpty: Bool { samples.isEmpty }

    /// Parses file names of the form `piano_060_loud.wav`.
    public static func parse(fileName: String) -> (midi: Int, layer: PianoSample.Layer)? {
        let base = fileName.split(separator: ".").first.map(String.init) ?? fileName
        let parts = base.split(separator: "_")
        guard parts.count == 3, parts[0] == "piano", let midi = Int(parts[1]), let layer = PianoSample.Layer(rawValue: String(parts[2])) else { return nil }
        return (midi, layer)
    }

    public func layer(for velocity: Float) -> PianoSample.Layer {
        velocity >= layerSplit ? .loud : .soft
    }

    /// Index of the best sample for a key: same layer when available, nearest root.
    public func sampleIndex(for midi: Int, velocity: Float) -> Int? {
        let wanted = layer(for: velocity)
        var best: Int?
        var bestScore = Int.max
        for (i, s) in samples.enumerated() {
            let distance = abs(s.rootMIDI - midi) * 2 + (s.layer == wanted ? 0 : 100)
            if distance < bestScore { bestScore = distance; best = i }
        }
        return best
    }

    /// Gain applied on top of the layer's recorded loudness for a given velocity.
    public func gain(for velocity: Float) -> Float {
        let v = max(0, min(1, velocity))
        if v >= layerSplit {
            return 0.55 + 0.45 * (v - layerSplit) / (1 - layerSplit)
        }
        return 0.45 + 0.55 * v / layerSplit
    }
}

/// Real-time polyphonic sample player. Not thread-safe: call every method from the audio render
/// thread (the app forwards UI commands through a lock-free-on-the-audio-side queue).
/// All storage is preallocated, so `render` never allocates.
public final class PianoSynth {
    public enum Command: Equatable, Sendable {
        case noteOn(midi: Int, velocity: Float)
        case noteOff(midi: Int)
        case sustain(Bool)
        case allNotesOff
        case click(accent: Bool)
        case volume(Float)
    }

    struct Voice {
        enum State { case idle, held, sustained, releasing }
        var state: State = .idle
        var midi = 0
        var sample = 0
        var position = 0.0
        var increment = 1.0
        var gain: Float = 0
        var envelope: Float = 1
        var releaseCoefficient: Float = 0.999
        var age = 0
    }

    public let outputSampleRate: Double
    public let maxVoices: Int
    public private(set) var bank: SampleBank
    public private(set) var sustainPedal = false
    public private(set) var volume: Float = 0.8

    private var voices: [Voice]
    private var ageCounter = 0
    private var smoothedVolume: Float = 0.8
    // Metronome click (a short decaying sine burst).
    private var clickPhase: Double = 0
    private var clickFrequency: Double = 1000
    private var clickRemaining = 0
    private var clickLength = 0

    public init(bank: SampleBank, outputSampleRate: Double, maxVoices: Int = 48) {
        self.bank = bank
        self.outputSampleRate = outputSampleRate
        self.maxVoices = maxVoices
        voices = [Voice](repeating: Voice(), count: maxVoices)
    }

    public var activeVoiceCount: Int { voices.reduce(0) { $0 + ($1.state == .idle ? 0 : 1) } }

    public func isSounding(_ midi: Int) -> Bool {
        voices.contains { $0.state != .idle && $0.state != .releasing && $0.midi == midi }
    }

    public func apply(_ command: Command) {
        switch command {
        case let .noteOn(midi, velocity): noteOn(midi, velocity: velocity)
        case let .noteOff(midi): noteOff(midi)
        case let .sustain(on): setSustain(on)
        case .allNotesOff:
            for i in voices.indices where voices[i].state != .idle { release(i, seconds: 0.08) }
            sustainPedal = false
        case let .click(accent):
            clickFrequency = accent ? 1568 : 1046
            clickLength = Int(outputSampleRate * 0.04)
            clickRemaining = clickLength
            clickPhase = 0
        case let .volume(v): volume = max(0, min(1, v))
        }
    }

    public func noteOn(_ midi: Int, velocity: Float) {
        guard let s = bank.sampleIndex(for: midi, velocity: velocity) else { return }
        // A re-struck key damps its previous voice quickly, like a real hammer hitting a ringing string.
        for i in voices.indices where voices[i].state != .idle && voices[i].midi == midi {
            release(i, seconds: 0.03)
        }
        let slot = freeVoiceIndex()
        let sample = bank.samples[s]
        ageCounter += 1
        voices[slot] = Voice(
            state: .held,
            midi: midi,
            sample: s,
            position: 0,
            increment: pow(2, Double(midi - sample.rootMIDI) / 12) * sample.sampleRate / outputSampleRate,
            gain: bank.gain(for: velocity),
            envelope: 1,
            releaseCoefficient: 1,
            age: ageCounter
        )
    }

    public func noteOff(_ midi: Int) {
        for i in voices.indices where voices[i].midi == midi && voices[i].state == .held {
            if sustainPedal {
                voices[i].state = .sustained
            } else {
                release(i, seconds: PianoSynth.damperTime(for: midi))
            }
        }
    }

    public func setSustain(_ on: Bool) {
        sustainPedal = on
        if !on {
            for i in voices.indices where voices[i].state == .sustained {
                release(i, seconds: PianoSynth.damperTime(for: voices[i].midi))
            }
        }
    }

    /// Lower strings take longer to damp.
    static func damperTime(for midi: Int) -> Double {
        let t = Double(max(21, min(108, midi)) - 21) / 87
        return 0.45 - 0.33 * t
    }

    private func release(_ i: Int, seconds: Double) {
        voices[i].state = .releasing
        // envelope reaches −60 dB after `seconds`.
        voices[i].releaseCoefficient = Float(pow(0.001, 1 / max(1, seconds * outputSampleRate)))
    }

    private func freeVoiceIndex() -> Int {
        if let idle = voices.firstIndex(where: { $0.state == .idle }) { return idle }
        // Steal the oldest releasing voice, else the oldest voice.
        var candidate = 0
        var oldest = Int.max
        for (i, v) in voices.enumerated() where v.state == .releasing && v.age < oldest { oldest = v.age; candidate = i }
        if oldest != Int.max { return candidate }
        for (i, v) in voices.enumerated() where v.age < oldest { oldest = v.age; candidate = i }
        return candidate
    }

    /// Renders `frameCount` mono frames into `buffer` (overwrites).
    public func render(into buffer: UnsafeMutablePointer<Float>, frameCount: Int) {
        for f in 0..<frameCount { buffer[f] = 0 }
        bank.samples.withUnsafeBufferPointer { samples in
            for i in 0..<voices.count where voices[i].state != .idle {
                var v = voices[i]
                samples[v.sample].frames.withUnsafeBufferPointer { data in
                    let last = data.count - 1
                    for f in 0..<frameCount {
                        let idx = Int(v.position)
                        if idx >= last { v.state = .idle; break }
                        let frac = Float(v.position - Double(idx))
                        let s = data[idx] + (data[idx + 1] - data[idx]) * frac
                        buffer[f] += s * v.gain * v.envelope
                        v.position += v.increment
                        if v.state == .releasing {
                            v.envelope *= v.releaseCoefficient
                            if v.envelope < 0.0005 { v.state = .idle; break }
                        }
                    }
                }
                voices[i] = v
            }
        }
        if clickRemaining > 0 {
            let w = 2 * Double.pi * clickFrequency / outputSampleRate
            for f in 0..<frameCount where clickRemaining > 0 {
                let env = Float(clickRemaining) / Float(max(1, clickLength))
                buffer[f] += Float(sin(clickPhase)) * 0.35 * env * env
                clickPhase += w
                clickRemaining -= 1
            }
        }
        // Smoothed master volume + soft limiter so big chords never clip harshly.
        for f in 0..<frameCount {
            smoothedVolume += (volume - smoothedVolume) * 0.002
            let x = buffer[f] * smoothedVolume
            buffer[f] = x / (1 + abs(x) * 0.25)
        }
    }
}
