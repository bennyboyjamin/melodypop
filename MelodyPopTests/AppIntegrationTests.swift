import MelodyPopKit
import SwiftData
import XCTest
@testable import MelodyPop

/// Integration tests that run inside the app with its real resources.
@MainActor
final class AudioIntegrationTests: XCTestCase {
    func testBundledPianoSamplesLoad() throws {
        let bank = try PianoAudioEngine.loadBank()
        XCTAssertEqual(bank.samples.count, 60) // 30 roots (every minor third, A0–C8) × soft/loud
        XCTAssertEqual(Set(bank.samples.map(\.rootMIDI)).count, 30)
        XCTAssertTrue(bank.samples.allSatisfy { $0.frames.count > 10_000 && $0.sampleRate == 44100 })
        // Every one of the 88 keys is within 1.5 semitones of a recorded root.
        for m in Pitch.pianoRange {
            let s = bank.samples[bank.sampleIndex(for: m, velocity: 0.8)!]
            XCTAssertLessThanOrEqual(abs(s.rootMIDI - m), 2, "key \(m)")
        }
    }

    /// Renders real piano notes through the synth and checks the pitch that comes out.
    func testRenderedPianoNotesHaveCorrectPitch() throws {
        let bank = try PianoAudioEngine.loadBank()
        let tracker = PitchTracker(sampleRate: 48000)
        for midi in [48, 55, 60, 62, 64, 67, 72, 79, 84] {
            let synth = PianoSynth(bank: bank, outputSampleRate: 48000)
            synth.noteOn(midi, velocity: 0.8)
            var out = [Float](repeating: 0, count: 48000 / 3)
            out.withUnsafeMutableBufferPointer { synth.render(into: $0.baseAddress!, frameCount: $0.count) }
            let e = tracker.analyze(Array(out.suffix(tracker.frameLength)))
            XCTAssertEqual(e.nearestPitch?.midi, midi, "rendered \(Pitch(midi)) but heard \(e.frequency) Hz")
            XCTAssertGreaterThan(e.confidence, 0.85)
        }
    }

    /// Feeds recorded acoustic-piano audio through the microphone pipeline.
    func testMicrophonePipelineOnRecordedPiano() throws {
        let bank = try PianoAudioEngine.loadBank()
        func sample(_ m: Int) -> [Float] {
            bank.samples.first { $0.rootMIDI == m && $0.layer == .loud }!.frames
        }
        var signal = [Float](repeating: 0, count: 8000)
        let melody = [60, 63, 66, 69, 72]
        for m in melody {
            signal += Array(sample(m).prefix(Int(0.5 * 44100)))
        }
        signal += [Float](repeating: 0, count: 20000)
        let tracker = PitchTracker(sampleRate: 44100)
        var seg = NoteSegmenter()
        var events: [NoteEvent] = []
        var end = tracker.frameLength
        while end <= signal.count {
            events += seg.process(tracker.analyze(Array(signal[(end - tracker.frameLength)..<end])), at: Double(end) / 44100)
            end += 1024
        }
        XCTAssertEqual(events.filter { $0.kind == .noteOn }.map(\.pitch.midi), melody)
    }
}

@MainActor
final class ProgressTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() async throws {
        container = DataStore.makeContainer(inMemory: true)
        context = ModelContext(container)
    }

    func testRecordingLessonResultUpdatesProgressAndStickers() throws {
        let student = StudentProfile(name: "Ada")
        context.insert(student)
        let lesson = Curriculum.lessons[0]
        let item = PracticeItem(lesson: lesson)
        let perfect = SessionResult(accuracy: 1, noteAccuracy: 1, timingAccuracy: 1, correctTargets: 7, totalTargets: 7, wrongNotes: 0, stars: 3)
        let stickers = ProgressService.record(item: item, result: perfect, seconds: 42, source: .touch, student: student, context: context)
        XCTAssertEqual(Set(stickers.map(\.id)), ["first-note", "perfect"])
        let p = try XCTUnwrap(student.progress(for: lesson.id))
        XCTAssertTrue(p.completed)
        XCTAssertEqual(p.bestStars, 3)
        XCTAssertEqual(p.attempts, 1)

        let weak = SessionResult(accuracy: 0.4, noteAccuracy: 0.4, timingAccuracy: 1, correctTargets: 3, totalTargets: 7, wrongNotes: 5, stars: 0)
        let again = ProgressService.record(item: item, result: weak, seconds: 30, source: .midi, student: student, context: context)
        XCTAssertTrue(again.isEmpty) // no duplicates
        XCTAssertEqual(p.attempts, 2)
        XCTAssertEqual(p.bestStars, 3)  // best is kept
        XCTAssertEqual(student.practiceLogs.count, 2)
        XCTAssertEqual(ProgressService.snapshot(for: student).sourcesUsed, [.touch, .midi])
    }

    func testGameAndSongLoggingFeedsRewards() throws {
        let student = StudentProfile(name: "Cy")
        context.insert(student)
        for _ in 0..<5 {
            ProgressService.log(activity: "game", itemID: PianoGame.keyFinder.logID, title: "Key Finder", seconds: 60, accuracy: 0.8, score: 640, source: .microphone, student: student, context: context)
        }
        let song = SongLibrary.songs[0]
        let result = SessionResult(accuracy: 0.9, noteAccuracy: 0.9, timingAccuracy: 0.9, correctTargets: 9, totalTargets: 10, wrongNotes: 1, stars: 3)
        let stickers = ProgressService.record(item: PracticeItem(song: song), result: result, seconds: 30, source: .midi, student: student, context: context)
        XCTAssertTrue(Set(stickers.map(\.id)).isSuperset(of: ["gamer", "first-song"]))
        let snap = ProgressService.snapshot(for: student)
        XCTAssertEqual(snap.bestGameScore, 640)
        XCTAssertEqual(snap.songsCompleted, 1)
        XCTAssertTrue(student.lessonProgress.isEmpty) // songs don't create lesson progress
    }

    func testRecordingsPersist() throws {
        let student = StudentProfile(name: "Ben")
        context.insert(student)
        var rec = PerformanceRecorder()
        rec.start(at: 0)
        rec.record(NoteEvent(kind: .noteOn, pitch: Pitch(60), time: 0.1, source: .touch))
        rec.record(NoteEvent(kind: .noteOff, pitch: Pitch(60), time: 0.5, source: .touch))
        let saved = try SavedRecording(title: "Test", recording: rec.stop(at: 1))
        context.insert(saved)
        saved.student = student
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<SavedRecording>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].recording?.noteCount, 1)
        XCTAssertEqual(student.recordings.count, 1)
    }
}

@MainActor
final class PlayModeRoutingTests: XCTestCase {
    func testTouchEventsReachListenersAndHighlight() async {
        let play = PlayModeController(initialMode: .touch)
        await play.select(.touch, force: true)
        var received: [NoteEvent] = []
        let id = play.addListener { received.append($0) }
        play.touch.keyDown(60, velocity: 0.7, time: 1)
        play.touch.keyDown(64, velocity: 0.7, time: 1.01)
        XCTAssertEqual(play.pressedKeys, [60, 64])
        play.touch.keyUp(60, time: 1.2)
        XCTAssertEqual(play.pressedKeys, [64])
        XCTAssertEqual(received.map(\.kind), [.noteOn, .noteOn, .noteOff])
        XCTAssertEqual(play.lastNote, Pitch(64))
        play.removeListener(id)
        play.touch.keyDown(67, velocity: 0.7, time: 2)
        XCTAssertEqual(received.count, 3)
    }

    func testLessonOneThroughSharedEngineSurvivesModeSwitch() async {
        let play = PlayModeController(initialMode: .touch)
        await play.select(.touch, force: true)
        let item = PracticeItem(lesson: Curriculum.lessons[0])
        let model = PracticePlayerModel(item: item, source: .touch)
        var finished: SessionResult?
        model.onFinished = { r, _, _ in finished = r }
        model.attach(to: play)
        model.start()
        let total = item.piece.notes.count
        for i in 0..<3 {
            play.touch.keyDown(60, velocity: 0.7, time: Double(i))
            play.touch.keyUp(60, time: Double(i) + 0.1)
        }
        XCTAssertEqual(model.session.completedCount, 3)
        // Switch to MIDI mid-lesson (no keyboard attached → paused with a setup message) and back.
        model.modeWillChange()
        await play.select(.midi)
        model.modeDidChange(to: .midi)
        XCTAssertEqual(model.session.completedCount, 3)
        model.modeWillChange()
        await play.select(.touch)
        model.modeDidChange(to: .touch)
        if case .paused = model.phase { model.resume() }
        XCTAssertEqual(model.phase, .playing)
        for i in 3..<total {
            play.touch.keyDown(60, velocity: 0.7, time: Double(i))
            play.touch.keyUp(60, time: Double(i) + 0.1)
        }
        XCTAssertEqual(model.phase, .finished)
        XCTAssertEqual(finished?.accuracy, 1)
        XCTAssertEqual(finished?.totalTargets, total)
        model.detach()
    }
}
