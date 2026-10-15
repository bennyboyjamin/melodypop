import XCTest
@testable import MelodyPopKit

final class CurriculumTests: XCTestCase {
    func testThirtyLessonsInFiveUnits() {
        XCTAssertEqual(Curriculum.lessons.count, 30)
        XCTAssertEqual(Curriculum.lessons.map(\.id), Array(1...30))
        for unit in Curriculum.units {
            let ids = Curriculum.lessons.filter { $0.unit == unit.id }.map(\.id)
            XCTAssertEqual(ids, Array(RewardRules.lessons(inUnit: unit.id)), "unit \(unit.id)")
        }
    }

    func testEveryLessonIsPlayableAndWellFormed() {
        for lesson in Curriculum.lessons {
            let piece = lesson.piece
            XCTAssertFalse(piece.notes.isEmpty, "lesson \(lesson.id)")
            XCTAssertTrue(piece.allPitches.allSatisfy { Pitch.pianoRange.contains($0.midi) })
            // Bars are complete: the music ends on a bar line.
            let end = piece.notes.map(\.endBeat).max()!
            XCTAssertEqual(end.truncatingRemainder(dividingBy: Double(piece.beatsPerBar)), 0, accuracy: 1e-9, "lesson \(lesson.id) ends mid-bar")
            XCTAssertFalse(lesson.title.isEmpty)
            XCTAssertFalse(lesson.tip.isEmpty)
            // Each hand plays one thing at a time (chords are written as one ScoreNote).
            for hand in Hand.allCases {
                let notes = piece.notes.filter { $0.hand == hand }.sorted { $0.startBeat < $1.startBeat }
                for (a, b) in zip(notes, notes.dropFirst()) {
                    XCTAssertLessThanOrEqual(a.endBeat, b.startBeat + 1e-9, "lesson \(lesson.id) overlapping \(hand) notes")
                }
            }
        }
    }

    func testCurriculumCoversRequiredSkills() {
        let kinds = Set(Curriculum.lessons.map(\.kind))
        XCTAssertTrue(kinds.isSuperset(of: [.noteFinding, .rhythm, .melody, .scale, .twoHands, .chords]))
        XCTAssertTrue(Curriculum.lessons.contains { $0.piece.usesBothHands })
        XCTAssertTrue(Curriculum.lessons.contains { $0.mode == .timed })
        XCTAssertTrue(Curriculum.lessons.contains { $0.mode == .waitForNotes })
    }

    func testMicrophoneCanPlayAllSingleNoteLessons() {
        let micLessons = Curriculum.lessons.filter { $0.isAvailable(for: .microphone) }
        let chordLessons = Curriculum.lessons.filter(\.requiresPolyphony)
        XCTAssertEqual(micLessons.count + chordLessons.count, 30)
        XCTAssertEqual(Set(chordLessons.map(\.id)), [26, 27, 28, 29, 30])
        XCTAssertTrue(Curriculum.lesson(id: 25)!.usesBothHandsWithoutOverlap)
    }

    func testSongsAreValid() {
        XCTAssertGreaterThanOrEqual(SongLibrary.songs.count, 12)
        XCTAssertEqual(Set(SongLibrary.songs.map(\.id)).count, SongLibrary.songs.count)
        for s in SongLibrary.songs {
            let end = s.piece.notes.map(\.endBeat).max()!
            XCTAssertEqual(end.truncatingRemainder(dividingBy: Double(s.piece.beatsPerBar)), 0, accuracy: 1e-9, s.title)
            XCTAssertTrue((1...3).contains(s.level))
        }
        XCTAssertTrue(SongLibrary.songs.contains { !$0.isPremium })
    }

    func testEntitlements() {
        XCTAssertFalse(Entitlements.isLessonLocked(10, hasPlus: false))
        XCTAssertTrue(Entitlements.isLessonLocked(11, hasPlus: false))
        XCTAssertFalse(Entitlements.isLessonLocked(30, hasPlus: true))
        let premium = SongLibrary.songs.first(where: \.isPremium)!
        XCTAssertTrue(Entitlements.isSongLocked(premium, hasPlus: false))
        XCTAssertFalse(Entitlements.isSongLocked(premium, hasPlus: true))
    }
}

private extension Lesson {
    var usesBothHandsWithoutOverlap: Bool { piece.usesBothHands && !piece.hasSimultaneousNotes }
}

final class GameTests: XCTestCase {
    func testNoteQuizScoringAndTimeouts() {
        var g = SeededGenerator(seed: 1)
        let pool = [60, 62, 64, 65, 67].map(Pitch.init)
        var quiz = NoteQuiz(kind: .exactPitch, pool: pool, count: 3, timeLimit: 5, generator: &g)
        XCTAssertEqual(quiz.rounds.count, 3)
        XCTAssertTrue(zip(quiz.rounds, quiz.rounds.dropFirst()).allSatisfy { $0.target != $1.target })

        quiz.beginRound(at: 0)
        let first = quiz.current!.target
        let wrong = pool.first { $0 != first }!
        XCTAssertFalse(quiz.answer(wrong, at: 1))
        XCTAssertTrue(quiz.answer(first, at: 2.5))      // 1 mistake, half the time used
        quiz.beginRound(at: 10)
        XCTAssertTrue(quiz.answer(quiz.current!.target, at: 10)) // instant
        quiz.beginRound(at: 20)
        XCTAssertFalse(quiz.checkTimeout(at: 24))
        XCTAssertTrue(quiz.checkTimeout(at: 25))
        XCTAssertTrue(quiz.isFinished)
        XCTAssertEqual(quiz.correctCount, 2)
        XCTAssertEqual(quiz.score, (100 + 25 - 10) + (100 + 50))
        XCTAssertEqual(quiz.accuracy, 2.0 / 3.0, accuracy: 1e-9)
    }

    func testKeyFinderAcceptsAnyOctave() {
        var g = SeededGenerator(seed: 3)
        var quiz = NoteQuiz(kind: .letterName, pool: [Pitch(65)], count: 1, generator: &g)
        quiz.beginRound(at: 0)
        XCTAssertTrue(quiz.matches(Pitch(41)))   // F2
        XCTAssertTrue(quiz.matches(Pitch(89)))   // F6
        XCTAssertFalse(quiz.matches(Pitch(66)))  // F♯
        XCTAssertTrue(quiz.answer(Pitch(77), at: 1))
    }

    func testMelodyMemoryGrowsAndEndsOnMistake() {
        var g = SeededGenerator(seed: 9)
        var game = MelodyMemory(pool: [60, 62, 64].map(Pitch.init))
        game.nextRound(using: &g)
        XCTAssertEqual(game.play(game.sequence[0]), .roundComplete)
        game.nextRound(using: &g)
        XCTAssertEqual(game.sequence.count, 2)
        XCTAssertEqual(game.play(game.sequence[0]), .correct)
        XCTAssertEqual(game.play(game.sequence[1]), .roundComplete)
        XCTAssertEqual(game.bestLength, 2)
        game.nextRound(using: &g)
        let wrong = [60, 62, 64].map(Pitch.init).first { $0 != game.sequence[0] }!
        XCTAssertEqual(game.play(wrong), .wrong)
        XCTAssertTrue(game.isOver)
        XCTAssertEqual(game.play(game.sequence[0]), .ignored)
        XCTAssertEqual(game.score, 100)
    }
}

final class RewardTests: XCTestCase {
    let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    func day(_ n: Int) -> Date { Date(timeIntervalSince1970: Double(n) * 86400 + 3600) }

    func testStreaks() {
        let days = [day(1), day(2), day(2), day(3), day(5), day(6)]
        XCTAssertEqual(RewardRules.longestStreak(days: days, calendar: cal), 3)
        XCTAssertEqual(RewardRules.currentStreak(days: days, today: day(6), calendar: cal), 2)
        XCTAssertEqual(RewardRules.currentStreak(days: days, today: day(7), calendar: cal), 2) // still alive today
        XCTAssertEqual(RewardRules.currentStreak(days: days, today: day(8), calendar: cal), 0)
        XCTAssertEqual(RewardRules.currentStreak(days: [], today: day(1), calendar: cal), 0)
    }

    func testStickerRules() {
        var s = ProgressSnapshot()
        XCTAssertTrue(RewardRules.earned(s, calendar: cal).isEmpty)
        s.completedLessons = Set(1...6)
        s.totalStars = 26
        s.practiceDays = [day(1), day(2), day(3)]
        s.sourcesUsed = Set(InputSource.allCases)
        s.recordings = 1
        let earned = RewardRules.earned(s, calendar: cal)
        XCTAssertEqual(earned, ["first-note", "unit-1", "stars-25", "streak-3", "all-modes", "composer"])
        XCTAssertTrue(earned.isSubset(of: Set(RewardRules.all.map(\.id))))
    }
}
