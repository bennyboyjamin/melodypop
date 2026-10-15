import Foundation
@testable import MelodyPopKit

/// Piano-like synthetic tones: a struck string with decaying, slightly inharmonic partials.
enum TestSignals {
    static func pianoTone(midi: Int, seconds: Double, sampleRate: Double = 44100, amplitude: Double = 0.5) -> [Float] {
        let f0 = Pitch.frequency(ofMIDI: Double(midi))
        let n = Int(seconds * sampleRate)
        let partials: [(Double, Double)] = [(1, 1.0), (2, 0.55), (3, 0.3), (4, 0.18), (5, 0.1), (6, 0.06)]
        let b = 0.0004 // inharmonicity
        var out = [Float](repeating: 0, count: n)
        for (k, a) in partials {
            let fk = f0 * k * (1 + b * k * k).squareRoot()
            guard fk < sampleRate / 2 else { continue }
            let decay = 1.5 + k * 1.2
            let w = 2 * Double.pi * fk / sampleRate
            for i in 0..<n {
                let t = Double(i) / sampleRate
                let attack = min(1, t / 0.004)
                out[i] += Float(amplitude * a * attack * exp(-decay * t) * sin(w * Double(i)))
            }
        }
        return out
    }

    static func noise(seconds: Double, level: Float, sampleRate: Double = 44100, seed: UInt64 = 7) -> [Float] {
        var g = SeededGenerator(seed: seed)
        return (0..<Int(seconds * sampleRate)).map { _ in Float.random(in: -level...level, using: &g) }
    }

    static func silence(seconds: Double, sampleRate: Double = 44100) -> [Float] {
        [Float](repeating: 0, count: Int(seconds * sampleRate))
    }

    static func sine(frequency: Double, seconds: Double, sampleRate: Double) -> [Float] {
        (0..<Int(seconds * sampleRate)).map { Float(0.8 * sin(2 * .pi * frequency * Double($0) / sampleRate)) }
    }

    /// Runs the same pipeline the app runs: hop-sized frames → tracker → segmenter.
    static func detect(_ signal: [Float], sampleRate: Double = 44100, hop: Int = 1024, gate: Double = 0.01) -> [NoteEvent] {
        let tracker = PitchTracker(sampleRate: sampleRate)
        var config = NoteSegmenter.Configuration()
        config.noiseGate = gate
        var segmenter = NoteSegmenter(configuration: config)
        var events: [NoteEvent] = []
        var end = tracker.frameLength
        while end <= signal.count {
            let estimate = tracker.analyze(Array(signal[(end - tracker.frameLength)..<end]))
            events += segmenter.process(estimate, at: Double(end) / sampleRate)
            end += hop
        }
        events += segmenter.finish(at: Double(signal.count) / sampleRate)
        return events
    }
}

struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
