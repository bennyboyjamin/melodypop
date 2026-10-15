import XCTest
@testable import MelodyPopKit

final class PitchTests: XCTestCase {
    func testNamesAndFrequencies() {
        XCTAssertEqual(Pitch.middleC.fullName, "C4")
        XCTAssertEqual(Pitch(61).fullName, "C♯4")
        XCTAssertEqual(Pitch(21).fullName, "A0")
        XCTAssertEqual(Pitch(108).fullName, "C8")
        XCTAssertEqual(Pitch(69).frequency, 440, accuracy: 1e-9)
        XCTAssertEqual(Pitch(60).frequency, 261.6256, accuracy: 1e-3)
        XCTAssertEqual(Pitch.midiValue(forFrequency: 880), 81, accuracy: 1e-9)
    }

    func testParsing() {
        XCTAssertEqual(Pitch(name: "C4")?.midi, 60)
        XCTAssertEqual(Pitch(name: "F#3")?.midi, 54)
        XCTAssertEqual(Pitch(name: "Bb2")?.midi, 46)
        XCTAssertEqual(Pitch(name: "C♯5")?.midi, 73)
        XCTAssertEqual(Pitch(name: "A0")?.midi, 21)
        XCTAssertNil(Pitch(name: "H2"))
        XCTAssertNil(Pitch(name: "C"))
    }

    func testBlackKeysAndStaffSteps() {
        XCTAssertEqual((60...71).filter { Pitch($0).isBlackKey }, [61, 63, 66, 68, 70])
        XCTAssertEqual(Pitch(60).diatonicStep, 28)
        XCTAssertEqual(Pitch(62).diatonicStep, 29)
        XCTAssertEqual(Pitch(61).diatonicStep, 28) // C♯ sits on C's line
        XCTAssertEqual(Pitch(72).diatonicStep - Pitch(60).diatonicStep, 7)
    }
}

final class MIDIParserTests: XCTestCase {
    func testNoteOnOffAndVelocityZero() {
        var p = MIDIByteParser()
        let msgs = p.parse([0x90, 60, 100, 0x80, 60, 0, 0x91, 62, 0])
        XCTAssertEqual(msgs, [
            .noteOn(channel: 0, note: 60, velocity: 100),
            .noteOff(channel: 0, note: 60, velocity: 0),
            .noteOff(channel: 1, note: 62, velocity: 0),
        ])
    }

    func testRunningStatusAndRealtimeInterleaving() {
        var p = MIDIByteParser()
        let msgs = p.parse([0x90, 60, 90, 0xF8, 64, 80, 67, 0xFE, 70])
        XCTAssertEqual(msgs, [
            .noteOn(channel: 0, note: 60, velocity: 90),
            .noteOn(channel: 0, note: 64, velocity: 80),
            .noteOn(channel: 0, note: 67, velocity: 70),
        ])
    }

    func testMessagesSplitAcrossPackets() {
        var p = MIDIByteParser()
        XCTAssertEqual(p.parse([0x90, 60]), [])
        XCTAssertEqual(p.parse([77]), [.noteOn(channel: 0, note: 60, velocity: 77)])
    }

    func testSysExIsSkippedAndSustainParsed() {
        var p = MIDIByteParser()
        let msgs = p.parse([0xF0, 0x7E, 0x01, 0x02, 0xF7, 0xB0, 64, 127, 0xC0, 5, 0xB0, 64, 0])
        XCTAssertEqual(msgs, [
            .controlChange(channel: 0, controller: 64, value: 127),
            .other,
            .controlChange(channel: 0, controller: 64, value: 0),
        ])
    }

    func testUMPMIDI1AndMIDI2() {
        let midi1On: UInt32 = 0x2090_3C64      // group 0, note on ch0, C4 vel 100
        let midi1Off: UInt32 = 0x2080_3C00
        let utility: UInt32 = 0x0000_0000      // NOOP, skipped
        let midi2OnHi: UInt32 = 0x4091_4000    // note on ch1, E4
        let midi2OnLo: UInt32 = 0xC800_0000    // velocity16 = 0xC800 → 7-bit 100
        let msgs = UMPParser.messages(from: [midi1On, utility, midi1Off, midi2OnHi, midi2OnLo])
        XCTAssertEqual(msgs, [
            .noteOn(channel: 0, note: 60, velocity: 100),
            .noteOff(channel: 0, note: 60, velocity: 0),
            .noteOn(channel: 1, note: 64, velocity: 100),
        ])
    }
}

final class KeyboardLayoutTests: XCTestCase {
    func testFullPianoHas52WhiteAnd36BlackKeys() {
        let l = KeyboardLayout(whiteKeyWidth: 40, height: 200)
        XCTAssertEqual(l.whiteKeyCount, 52)
        XCTAssertEqual(l.blackKeyCount, 36)
        XCTAssertEqual(l.totalWidth, 52 * 40)
        XCTAssertEqual(l.midiForWhiteIndex(0), 21)
        XCTAssertEqual(l.midiForWhiteIndex(51), 108)
        XCTAssertEqual(l.whiteIndex(of: 60), 23)
    }

    func testHitTestingEveryKeyCentre() {
        var l = KeyboardLayout(whiteKeyWidth: 40, height: 200)
        l.scrollOffset = 20
        for m in l.visibleKeys(viewWidth: 600) {
            let f = Pitch(m).isBlackKey ? l.frame(for: m) : l.uncoveredFrame(forWhite: m)
            guard f.x >= 0, f.maxX <= 600 else { continue }
            XCTAssertEqual(l.key(atX: f.midX, y: f.midY), m, "key \(Pitch(m))")
        }
    }

    func testBlackKeyWinsOverlapAndWhiteBelowIt() {
        let l = KeyboardLayout(range: 60...72, whiteKeyWidth: 50, height: 200)
        let cs = l.frame(for: 61)
        XCTAssertEqual(l.key(atX: cs.midX, y: 20), 61)
        XCTAssertEqual(l.key(atX: cs.midX, y: 190), cs.midX < 50 ? 60 : 62)
        XCTAssertNil(l.key(atX: -5, y: 50))
        XCTAssertNil(l.key(atX: 10, y: 250))
    }

    func testOctaveOffsets() {
        let l = KeyboardLayout(whiteKeyWidth: 40, height: 200)
        XCTAssertEqual(l.offset(showingOctaveOf: 64, visibleWhiteKeys: 14), 23) // C4
        XCTAssertEqual(l.offset(showingOctaveOf: 105, visibleWhiteKeys: 14), 38) // clamped to the top
        XCTAssertEqual(l.offset(showingOctaveOf: 22, visibleWhiteKeys: 14), 0)
        let centred = l.offset(centering: 60, 67, visibleWhiteKeys: 14)
        XCTAssertEqual(centred, 23 + 2.5 - 7, accuracy: 1e-9)
    }
}

final class PianoSynthTests: XCTestCase {
    func makeSynth() -> PianoSynth {
        let sr = 44100.0
        let samples = [48, 60, 72].flatMap { root in
            PianoSample.Layer.allCases.map { layer in
                PianoSample(rootMIDI: root, layer: layer, frames: TestSignals.sine(frequency: Pitch(root).frequency, seconds: 2, sampleRate: sr).map { $0 * (layer == .loud ? 0.8 : 0.4) }, sampleRate: sr)
            }
        }
        return PianoSynth(bank: SampleBank(samples: samples), outputSampleRate: sr)
    }

    func render(_ synth: PianoSynth, seconds: Double) -> [Float] {
        var out = [Float](repeating: 0, count: Int(seconds * 44100))
        let block = 256
        var i = 0
        while i < out.count {
            let n = min(block, out.count - i)
            out.withUnsafeMutableBufferPointer { synth.render(into: $0.baseAddress! + i, frameCount: n) }
            i += n
        }
        return out
    }

    func testSampleSelectionAndFileNames() {
        let bank = makeSynth().bank
        let idx = bank.sampleIndex(for: 62, velocity: 0.9)!
        XCTAssertEqual(bank.samples[idx].rootMIDI, 60)
        XCTAssertEqual(bank.samples[idx].layer, .loud)
        XCTAssertEqual(bank.samples[bank.sampleIndex(for: 70, velocity: 0.2)!].rootMIDI, 72)
        XCTAssertEqual(bank.samples[bank.sampleIndex(for: 70, velocity: 0.2)!].layer, .soft)
        let parsed = SampleBank.parse(fileName: "piano_060_loud.wav")
        XCTAssertEqual(parsed?.midi, 60)
        XCTAssertEqual(parsed?.layer, .loud)
        XCTAssertNil(SampleBank.parse(fileName: "readme.txt"))
        XCTAssertGreaterThan(bank.gain(for: 1), bank.gain(for: 0.6))
    }

    func testPitchShiftedNoteHasCorrectFrequency() {
        let synth = makeSynth()
        synth.noteOn(64, velocity: 0.8) // E4 from the C4 sample
        let out = render(synth, seconds: 0.3)
        let tracker = PitchTracker(sampleRate: 44100)
        let e = tracker.analyze(Array(out.suffix(tracker.frameLength)))
        XCTAssertEqual(e.nearestPitch?.midi, 64)
        XCTAssertLessThan(abs(e.centsOff!), 5)
    }

    func testChordPolyphonyAndRelease() {
        let synth = makeSynth()
        for m in [60, 64, 67] { synth.noteOn(m, velocity: 0.7) }
        XCTAssertEqual(synth.activeVoiceCount, 3)
        _ = render(synth, seconds: 0.1)
        for m in [60, 64, 67] { synth.noteOff(m) }
        _ = render(synth, seconds: 0.6)
        XCTAssertEqual(synth.activeVoiceCount, 0)
        let after = render(synth, seconds: 0.05)
        XCTAssertEqual(after.map { abs($0) }.max(), 0)
    }

    func testSustainPedalHoldsNotesUntilReleased() {
        let synth = makeSynth()
        synth.setSustain(true)
        synth.noteOn(60, velocity: 0.7)
        synth.noteOff(60)
        _ = render(synth, seconds: 0.8)
        XCTAssertEqual(synth.activeVoiceCount, 1)
        synth.setSustain(false)
        _ = render(synth, seconds: 0.6)
        XCTAssertEqual(synth.activeVoiceCount, 0)
    }

    func testRestrikeAndVoiceStealingNeverExceedPool() {
        let synth = makeSynth()
        for _ in 0..<5 { synth.noteOn(60, velocity: 0.7) }
        XCTAssertLessThanOrEqual(synth.activeVoiceCount, 5)
        XCTAssertEqual((0..<synth.maxVoices).count, 48)
        for m in 21...108 { synth.noteOn(m, velocity: 0.5) }
        XCTAssertEqual(synth.activeVoiceCount, synth.maxVoices)
        let out = render(synth, seconds: 0.05)
        XCTAssertTrue(out.allSatisfy { abs($0) < 4.0 && $0.isFinite }) // limiter keeps it bounded
    }

    func testVolumeAndClick() {
        let synth = makeSynth()
        synth.apply(.volume(0))
        synth.apply(.click(accent: true))
        let silent = render(synth, seconds: 0.5)
        XCTAssertLessThan(silent.suffix(1000).map { abs($0) }.max()!, 0.01)
        synth.apply(.volume(1))
        _ = render(synth, seconds: 0.5)
        synth.apply(.click(accent: false))
        let click = render(synth, seconds: 0.02)
        XCTAssertGreaterThan(click.map { abs($0) }.max()!, 0.05)
    }
}

final class NotationTests: XCTestCase {
    func testParsesDurationsRestsChordsFingers() throws {
        let notes = try Notation.parse("C4@1:q D4:e. | r:s E4+G4:h F#4:w", hand: .right)
        XCTAssertEqual(notes.count, 4)
        XCTAssertEqual(notes[0].finger, 1)
        XCTAssertEqual(notes[1].beats, 0.75)
        XCTAssertEqual(notes[2].startBeat, 2.0)
        XCTAssertEqual(notes[2].pitches.map(\.midi), [64, 67])
        XCTAssertEqual(notes[3].pitches.first?.midi, 66)
        XCTAssertEqual(notes[3].startBeat, 4)
    }

    func testFingeredChordsKeepAllNotes() throws {
        let notes = try Notation.parse("C4@1+E4@3+G4@5:w B3@1+D4+G4:h", hand: .right)
        XCTAssertEqual(notes[0].pitches.map(\.midi), [60, 64, 67])
        XCTAssertEqual(notes[0].finger, 1)
        XCTAssertEqual(notes[1].pitches.map(\.midi), [59, 62, 67])
        XCTAssertThrowsError(try Notation.parse("C4@x:q", hand: .right))
    }

    func testErrors() {
        XCTAssertThrowsError(try Notation.parse("C4", hand: .right))
        XCTAssertThrowsError(try Notation.parse("X4:q", hand: .right))
        XCTAssertThrowsError(try Notation.parse("C4:z", hand: .right))
    }

    func testTwoHandPiece() throws {
        let piece = try Piece(title: "t", tempo: 90, right: "E4:h E4:h", left: "C3:w")
        XCTAssertTrue(piece.usesBothHands)
        XCTAssertTrue(piece.hasSimultaneousNotes)
        XCTAssertFalse(piece.hasChords)
        XCTAssertEqual(Set(piece.notes.map(\.id)).count, 3)
        XCTAssertEqual(piece.totalBeats, 4)
    }
}

final class RecorderTests: XCTestCase {
    func ev(_ k: NoteEvent.Kind, _ m: Int, _ t: Double) -> NoteEvent {
        NoteEvent(kind: k, pitch: Pitch(m), velocity: 0.7, time: t, source: .touch)
    }

    func testRecordStopClosesHeldNotesAndRoundTrips() throws {
        var r = PerformanceRecorder()
        r.record(ev(.noteOn, 60, 1)) // ignored: not recording
        r.start(at: 10)
        r.record(ev(.noteOn, 60, 10.5))
        r.recordPedal(down: true, at: 10.6)
        r.record(ev(.noteOn, 64, 11))
        r.record(ev(.noteOff, 60, 11.5))
        r.record(ev(.noteOff, 62, 11.6)) // never pressed: ignored
        let rec = r.stop(at: 12)
        XCTAssertEqual(rec.duration, 2)
        XCTAssertEqual(rec.noteCount, 2)
        XCTAssertEqual(rec.events.last, .init(offset: 2, kind: .noteOff, midi: 64, velocity: 0))
        XCTAssertEqual(rec.pedal.last?.down, false)
        XCTAssertEqual(try PerformanceRecording.decode(rec.encoded()), rec)

        var cursor = PlaybackCursor(recording: rec)
        XCTAssertEqual(cursor.advance(to: 0.5).notes.count, 1)
        XCTAssertEqual(cursor.advance(to: 1.0).notes.map(\.midi), [64])
        let rest = cursor.advance(to: 5)
        XCTAssertEqual(rest.notes.count, 2)
        XCTAssertTrue(cursor.isAtEnd)
    }
}
