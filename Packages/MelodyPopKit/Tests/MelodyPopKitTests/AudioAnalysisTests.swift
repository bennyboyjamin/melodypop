import XCTest
@testable import MelodyPopKit

final class FFTTests: XCTestCase {
    func testForwardInverseRoundTrip() {
        let fft = FFT(size: 64)
        let original = (0..<64).map { sin(Double($0) * 0.3) + 0.5 * cos(Double($0) * 1.7) }
        var re = original, im = [Double](repeating: 0, count: 64)
        fft.transform(real: &re, imag: &im)
        fft.transform(real: &re, imag: &im, inverse: true)
        for i in 0..<64 { XCTAssertEqual(re[i] / 64, original[i], accuracy: 1e-9) }
    }

    func testSinePeakBin() {
        let fft = FFT(size: 256)
        var re = (0..<256).map { sin(2 * Double.pi * 8 * Double($0) / 256) }
        var im = [Double](repeating: 0, count: 256)
        fft.transform(real: &re, imag: &im)
        let mags = (0..<128).map { (re[$0] * re[$0] + im[$0] * im[$0]).squareRoot() }
        XCTAssertEqual(mags.firstIndex(of: mags.max()!), 8)
    }
}

final class PitchTrackerTests: XCTestCase {
    func testDetectsPureSinesAcrossRange() {
        for sr in [44100.0, 48000.0] {
            let tracker = PitchTracker(sampleRate: sr)
            for f in [65.4, 110.0, 261.63, 440.0, 987.77, 2093.0] {
                let s = TestSignals.sine(frequency: f, seconds: 0.2, sampleRate: sr)
                let e = tracker.analyze(s)
                XCTAssertEqual(e.frequency, f, accuracy: f * 0.005, "sr \(sr) f \(f)")
                XCTAssertGreaterThan(e.confidence, 0.95)
            }
        }
    }

    func testDetectsPianoLikeTonesC2toC7() {
        let tracker = PitchTracker(sampleRate: 44100)
        for midi in stride(from: 36, through: 96, by: 5) {
            let tone = TestSignals.pianoTone(midi: midi, seconds: 0.3)
            let frame = Array(tone[2048..<(2048 + tracker.frameLength)])
            let e = tracker.analyze(frame)
            XCTAssertEqual(e.nearestPitch?.midi, midi, "midi \(midi) detected \(e.frequency) Hz")
            XCTAssertLessThan(abs(e.centsOff ?? 100), 30)
            XCTAssertGreaterThan(e.confidence, 0.85)
        }
    }

    func testNoiseHasLowConfidence() {
        let tracker = PitchTracker(sampleRate: 44100)
        let e = tracker.analyze(TestSignals.noise(seconds: 0.2, level: 0.3))
        XCTAssertLessThan(e.confidence, 0.85)
    }

    func testSilenceReportsNothing() {
        let tracker = PitchTracker(sampleRate: 44100)
        let e = tracker.analyze(TestSignals.silence(seconds: 0.2))
        XCTAssertEqual(e.frequency, 0)
        XCTAssertEqual(e.confidence, 0)
    }

    func testShortBufferIsRejected() {
        let tracker = PitchTracker(sampleRate: 44100)
        XCTAssertEqual(tracker.analyze([0.1, 0.2]).frequency, 0)
    }
}

final class NoteSegmenterTests: XCTestCase {
    func testMelodyOnsetsAndPitches() {
        var signal = TestSignals.silence(seconds: 0.2)
        let melody = [60, 64, 67, 72]
        for m in melody {
            signal += TestSignals.pianoTone(midi: m, seconds: 0.45)
            signal += TestSignals.silence(seconds: 0.1)
        }
        let events = TestSignals.detect(signal)
        let ons = events.filter { $0.kind == .noteOn }
        XCTAssertEqual(ons.map(\.pitch.midi), melody)
        // Onsets land within ~90 ms of the true strike times.
        let truth = [0.2, 0.75, 1.3, 1.85]
        for (e, t) in zip(ons, truth) { XCTAssertEqual(e.time, t, accuracy: 0.09) }
        XCTAssertTrue(events.filter { $0.kind == .noteOff }.allSatisfy(\.isInferred))
        XCTAssertTrue(ons.allSatisfy { $0.source == .microphone && $0.confidence >= 0.85 })
    }

    func testRepeatedSameNoteIsReattacked() {
        var signal = TestSignals.silence(seconds: 0.1)
        for _ in 0..<3 {
            // Strike, let it ring briefly, strike again before it fades below the gate.
            signal += TestSignals.pianoTone(midi: 62, seconds: 0.5)
        }
        let ons = TestSignals.detect(signal).filter { $0.kind == .noteOn }
        XCTAssertEqual(ons.count, 3)
        XCTAssertTrue(ons.allSatisfy { $0.pitch.midi == 62 })
    }

    func testBackgroundNoiseProducesNoNotes() {
        let events = TestSignals.detect(TestSignals.noise(seconds: 1.5, level: 0.02), gate: 0.03)
        XCTAssertTrue(events.isEmpty)
    }

    func testEveryNoteOnHasMatchingNoteOff() {
        var signal = TestSignals.pianoTone(midi: 57, seconds: 0.6)
        signal += TestSignals.pianoTone(midi: 59, seconds: 0.6)
        let events = TestSignals.detect(signal)
        XCTAssertEqual(events.filter { $0.kind == .noteOn }.count, events.filter { $0.kind == .noteOff }.count)
    }

    func testNoiseCalibratorGate() {
        var c = NoiseCalibrator()
        XCTAssertEqual(c.recommendedGate, 0.01)
        for _ in 0..<50 { c.add(rms: 0.002) }
        XCTAssertEqual(c.recommendedGate, 0.006, accuracy: 1e-9)
        var quiet = NoiseCalibrator()
        for _ in 0..<50 { quiet.add(rms: 0.0001) }
        XCTAssertEqual(quiet.recommendedGate, 0.004)
    }
}
