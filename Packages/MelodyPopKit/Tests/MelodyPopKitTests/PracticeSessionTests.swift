import XCTest
@testable import MelodyPopKit

final class PracticeSessionTests: XCTestCase {
    func on(_ m: Int, _ t: Double, _ source: InputSource = .midi) -> NoteEvent {
        // Undo latency compensation so tests can reason in "true" times.
        NoteEvent(kind: .noteOn, pitch: Pitch(m), velocity: 0.8, time: t + source.capabilities.latencyCompensation, source: source)
    }

    func piece(_ right: String, left: String? = nil, tempo: Double = 60) -> Piece {
        try! Piece(title: "test", tempo: tempo, right: right, left: left)
    }

    // MARK: Wait mode

    func testWaitModePerfectRun() {
        let s = PracticeSession(piece: piece("C4:q D4:q E4:q"), mode: .waitForNotes, capabilities: InputSource.touch.capabilities)
        XCTAssertFalse(s.handle(on(60, 0))) // not started yet
        s.start(at: 0)
        XCTAssertEqual(s.upcomingPitches(at: 0), [60])
        XCTAssertTrue(s.handle(on(60, 1)))
        XCTAssertEqual(s.upcomingPitches(at: 0), [62])
        s.handle(on(62, 2))
        s.handle(on(64, 3))
        XCTAssertTrue(s.isFinished)
        XCTAssertEqual(s.result.accuracy, 1)
        XCTAssertEqual(s.result.stars, 3)
        XCTAssertEqual(s.result.correctTargets, 3)
    }

    func testWaitModeWrongNotesLowerScore() {
        let s = PracticeSession(piece: piece("C4:q C4:q"), mode: .waitForNotes, capabilities: InputSource.touch.capabilities)
        s.start(at: 0)
        XCTAssertFalse(s.handle(on(62, 1)))
        s.handle(on(60, 2))     // good (one mistake)
        s.handle(on(61, 3)); s.handle(on(63, 3.1)); s.handle(on(65, 3.2))
        s.handle(on(60, 4))     // partial (three mistakes)
        XCTAssertTrue(s.isFinished)
        XCTAssertEqual(s.targets.map(\.grade), [.good, .partial])
        XCTAssertEqual(s.result.accuracy, (Grade.good.value + Grade.partial.value) / 2, accuracy: 1e-9)
        XCTAssertEqual(s.wrongNotes, 4)
    }

    func testWaitModeChordNeedsNotesTogether() {
        let s = PracticeSession(piece: piece("C4+E4+G4:w"), mode: .waitForNotes, capabilities: InputSource.touch.capabilities)
        s.start(at: 0)
        s.handle(on(60, 1))
        s.handle(on(64, 1.05))
        s.handle(on(67, 5))      // too late: earlier notes expire
        XCTAssertFalse(s.isFinished)
        s.handle(on(60, 5.1)); s.handle(on(64, 5.15))
        XCTAssertTrue(s.isFinished)
        XCTAssertEqual(s.result.accuracy, 1)
    }

    // MARK: Timed mode

    func testTimedModeGradesByTimingError() {
        // tempo 60 → one beat per second
        let s = PracticeSession(piece: piece("C4:q D4:q E4:q F4:q"), mode: .timed, capabilities: InputSource.midi.capabilities)
        s.start(at: 100)
        s.handle(on(60, 100.02))   // perfect
        s.handle(on(62, 101.15))   // good
        s.handle(on(64, 102.30))   // ok
        s.tick(at: 104)            // F4 never played → missed
        XCTAssertTrue(s.isFinished)
        XCTAssertEqual(s.targets.map(\.grade), [.perfect, .good, .ok, .missed])
        let expected = (1 + 0.85 + 0.6 + 0) / 4
        XCTAssertEqual(s.result.accuracy, expected, accuracy: 1e-9)
        XCTAssertEqual(s.result.noteAccuracy, 0.75)
        XCTAssertEqual(s.result.stars, SessionResult.stars(for: expected))
    }

    func testTimedModeWrongNotesPenalize() {
        let s = PracticeSession(piece: piece("C4:q C4:q"), mode: .timed, capabilities: InputSource.midi.capabilities)
        s.start(at: 0)
        s.handle(on(60, 0))
        XCTAssertFalse(s.handle(on(61, 0.5)))
        s.handle(on(60, 1))
        s.tick(at: 3)
        XCTAssertEqual(s.result.wrongNotes, 1)
        XCTAssertEqual(s.result.accuracy, 1 * 2 / 2.5, accuracy: 1e-9)
    }

    func testTimedModeEarlyLateBoundaries() {
        let s = PracticeSession(piece: piece("C4:q"), mode: .timed, capabilities: InputSource.midi.capabilities)
        s.start(at: 10)
        XCTAssertFalse(s.handle(on(60, 9.5)))   // far too early
        XCTAssertTrue(s.handle(on(60, 9.75)))   // early but inside the ok window
        XCTAssertEqual(s.targets[0].grade, .ok)
    }

    func testTimedModeChordPartialCredit() {
        let s = PracticeSession(piece: piece("C4+E4+G4:h"), mode: .timed, capabilities: InputSource.touch.capabilities)
        s.start(at: 0)
        s.handle(on(60, 0.0, .touch))
        s.handle(on(64, 0.02, .touch))
        s.tick(at: 2)
        XCTAssertEqual(s.targets[0].grade, .partial)
        XCTAssertEqual(s.targets[0].score, 2.0 / 3.0 * 1 * 0.8, accuracy: 1e-9)
    }

    func testPauseResumeKeepsBeatPosition() {
        let s = PracticeSession(piece: piece("C4:q D4:q E4:q"), mode: .timed, capabilities: InputSource.midi.capabilities)
        s.start(at: 0)
        s.handle(on(60, 0))
        s.pause(at: 0.5)
        XCTAssertFalse(s.handle(on(62, 1)))    // ignored while paused
        s.tick(at: 30)                         // time passes; nothing is missed
        XCTAssertEqual(s.completedCount, 1)
        s.resume(at: 50)
        XCTAssertEqual(s.beat(at: 50), 0.5, accuracy: 1e-9)
        s.handle(on(62, 50.5))                 // beat 1 is now at t = 50.5
        s.handle(on(64, 51.5))
        XCTAssertTrue(s.isFinished)
        XCTAssertEqual(s.result.accuracy, 1, accuracy: 1e-9)
    }

    func testTempoChangeMidRunPreservesBeat() {
        let s = PracticeSession(piece: piece("C4:q D4:q E4:q", tempo: 60), mode: .timed, capabilities: InputSource.midi.capabilities)
        s.start(at: 0)
        s.handle(on(60, 0))
        s.setTempoScale(0.5, at: 0.5)          // now 30 bpm: 2 s per beat
        XCTAssertEqual(s.beat(at: 0.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(s.time(ofBeat: 1), 1.5, accuracy: 1e-9)
        s.handle(on(62, 1.5))
        s.handle(on(64, 3.5))
        XCTAssertEqual(s.result.accuracy, 1, accuracy: 1e-9)
    }

    func testLatencyCompensationForMicrophone() {
        let s = PracticeSession(piece: piece("C4:q"), mode: .timed, capabilities: InputSource.microphone.capabilities)
        s.start(at: 0)
        // Raw microphone timestamp 70 ms late = on time after compensation.
        s.handle(NoteEvent(kind: .noteOn, pitch: Pitch(60), time: 0.07, source: .microphone, confidence: 0.9))
        XCTAssertEqual(s.targets[0].grade, .perfect)
    }

    // MARK: Switching input modes mid-lesson

    func testSwitchingToMicrophoneSimplifiesChordsAndKeepsProgress() {
        let p = piece("C4:q C4+E4+G4:q E4:q")
        let s = PracticeSession(piece: p, mode: .waitForNotes, capabilities: InputSource.touch.capabilities)
        s.start(at: 0)
        s.handle(on(60, 1, .touch))
        XCTAssertEqual(s.completedCount, 1)
        s.setCapabilities(InputSource.microphone.capabilities)
        XCTAssertEqual(s.completedCount, 1)
        XCTAssertEqual(s.targets[1].expected, [67])
        XCTAssertTrue(s.targets[1].simplified)
        s.handle(on(67, 2, .microphone))
        XCTAssertEqual(s.completedCount, 2)
        s.setCapabilities(InputSource.midi.capabilities)
        XCTAssertEqual(s.targets[2].expected, [64])
        XCTAssertTrue(s.targets[1].simplified)  // finished targets keep how they were graded
        s.handle(on(64, 3, .midi))
        XCTAssertTrue(s.isFinished)
    }

    func testUpcomingPitchesTimed() {
        let s = PracticeSession(piece: piece("C4:q D4:q E4:q"), mode: .timed, capabilities: InputSource.midi.capabilities)
        s.start(at: 0)
        XCTAssertEqual(s.upcomingPitches(at: 0), [60])
        XCTAssertEqual(s.upcomingPitches(at: 0.3), [60, 62])
        s.handle(on(60, 0.1))
        XCTAssertEqual(s.upcomingPitches(at: 0.3), [62])
    }

    func testLessonAvailabilityPerInput() {
        let lesson = Lesson(id: 99, unit: 1, title: "", goal: "", tip: "", kind: .chords, mode: .timed, piece: piece("C4+E4:q"))
        XCTAssertTrue(lesson.requiresPolyphony)
        XCTAssertFalse(lesson.isAvailable(for: .microphone))
        XCTAssertNotNil(lesson.unavailableReason(for: .microphone))
        XCTAssertTrue(lesson.isAvailable(for: .midi))
        XCTAssertTrue(lesson.isAvailable(for: .touch))
    }
}
