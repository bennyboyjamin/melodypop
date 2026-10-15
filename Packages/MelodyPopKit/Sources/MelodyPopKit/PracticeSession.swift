import Foundation

public enum EvaluationMode: String, Codable, Sendable {
    /// The session waits on each note until it is played (note finding, first melodies).
    case waitForNotes
    /// Notes must be played on the beat at the chosen tempo (rhythm, songs).
    case timed
}

public enum Grade: String, Codable, Sendable, Equatable {
    case perfect, good, ok, partial, missed
    public var value: Double {
        switch self {
        case .perfect: return 1
        case .good: return 0.85
        case .ok: return 0.6
        case .partial: return 0.4
        case .missed: return 0
        }
    }
    public var label: String {
        switch self {
        case .perfect: return "Perfect!"
        case .good: return "Great"
        case .ok: return "OK"
        case .partial: return "Almost"
        case .missed: return "Missed"
        }
    }
}

public struct TimingWindows: Equatable, Sendable {
    public var perfect: TimeInterval = 0.10
    public var good: TimeInterval = 0.20
    public var ok: TimeInterval = 0.32
    public init() {}

    public func grade(forError error: TimeInterval) -> Grade? {
        let e = abs(error)
        if e <= perfect { return .perfect }
        if e <= good { return .good }
        if e <= ok { return .ok }
        return nil
    }
}

public struct TargetState: Identifiable, Equatable, Sendable {
    public enum Status: String, Sendable { case upcoming, active, done }
    public let id: Int
    public let note: ScoreNote
    /// Pitches that must be played (a chord may be simplified for monophonic input).
    public var expected: Set<Int>
    /// MIDI → timing error in seconds (wait mode stores 0).
    public var matched: [Int: TimeInterval] = [:]
    public var matchTimes: [Int: TimeInterval] = [:]
    public var wrongAttempts = 0
    public var status: Status = .upcoming
    public var grade: Grade?
    public var score: Double = 0
    public var simplified = false

    public var remaining: Set<Int> { expected.subtracting(matched.keys) }
}

public struct SessionResult: Equatable, Codable, Sendable {
    public var accuracy: Double        // 0...1, the headline score
    public var noteAccuracy: Double    // fraction of targets fully played with the right notes
    public var timingAccuracy: Double  // mean timing grade of played targets (1 in wait mode)
    public var correctTargets: Int
    public var totalTargets: Int
    public var wrongNotes: Int
    public var stars: Int

    public static func stars(for accuracy: Double) -> Int {
        accuracy >= 0.9 ? 3 : accuracy >= 0.75 ? 2 : accuracy >= 0.5 ? 1 : 0
    }
}

/// The single lesson engine shared by all three play modes.
/// Feed it normalized `NoteEvent`s from any `PianoInput` and call `tick(at:)` regularly in timed mode.
/// It never looks at which device produced an event except to apply that source's latency
/// compensation and polyphony capability, so students can switch mode mid-lesson.
public final class PracticeSession {
    public let piece: Piece
    public let mode: EvaluationMode
    public var windows = TimingWindows()
    public private(set) var targets: [TargetState]
    public private(set) var wrongNotes = 0
    public private(set) var isRunning = false
    public private(set) var isPaused = false
    public private(set) var isFinished = false
    public private(set) var capabilities: InputCapabilities
    public private(set) var tempoScale: Double

    /// Wait mode: max spread between the notes of a chord.
    public var chordWindow: TimeInterval = 0.6

    // Timed-mode clock: beat(t) = anchorBeat + (t − anchorTime) / secondsPerBeat
    private var anchorTime: TimeInterval = 0
    private var anchorBeat: Double = 0
    private var pausedAt: TimeInterval?

    public init(piece: Piece, mode: EvaluationMode, capabilities: InputCapabilities, tempoScale: Double = 1) {
        self.piece = piece
        self.mode = mode
        self.capabilities = capabilities
        self.tempoScale = tempoScale
        self.targets = piece.notes.map { note in
            TargetState(id: note.id, note: note, expected: Set(note.pitches.map(\.midi)))
        }
        applyCapabilities()
    }

    public var secondsPerBeat: Double { 60 / (piece.tempo * tempoScale) }

    // MARK: Lifecycle

    /// Timed mode: `time` is when beat 0 sounds (call after the count-in). Wait mode: any time.
    public func start(at time: TimeInterval) {
        anchorTime = time
        anchorBeat = 0
        isRunning = true
        isPaused = false
        pausedAt = nil
        if mode == .waitForNotes { activateNextWaitTarget() }
    }

    public func pause(at time: TimeInterval) {
        guard isRunning, !isPaused, !isFinished else { return }
        isPaused = true
        pausedAt = time
    }

    /// Resumes so that the beat position continues from where it paused.
    public func resume(at time: TimeInterval) {
        guard isPaused, let p = pausedAt else { return }
        if mode == .timed {
            anchorBeat = beat(at: p)
            anchorTime = time
        }
        isPaused = false
        pausedAt = nil
    }

    /// Changing the play mode mid-lesson: progress is kept; chords are re-evaluated for the new input.
    public func setCapabilities(_ caps: InputCapabilities) {
        capabilities = caps
        applyCapabilities()
    }

    /// Changes tempo without jumping: the current beat position is preserved.
    public func setTempoScale(_ scale: Double, at time: TimeInterval) {
        let s = max(0.25, min(2, scale))
        if mode == .timed && isRunning {
            let reference = pausedAt ?? time
            anchorBeat = beat(at: reference)
            anchorTime = reference
            if isPaused { pausedAt = reference }
        }
        tempoScale = s
    }

    /// Beat position at host time `t` (timed mode).
    public func beat(at t: TimeInterval) -> Double {
        let effective = pausedAt.map { min($0, t) } ?? t
        return anchorBeat + (effective - anchorTime) / secondsPerBeat
    }

    public func time(ofBeat b: Double) -> TimeInterval {
        anchorTime + (b - anchorBeat) * secondsPerBeat
    }

    // MARK: Input

    /// Returns true if the event matched an expected note.
    @discardableResult
    public func handle(_ event: NoteEvent) -> Bool {
        guard isRunning, !isPaused, !isFinished, event.kind == .noteOn else { return false }
        switch mode {
        case .waitForNotes: return handleWait(event)
        case .timed: return handleTimed(event)
        }
    }

    private func handleWait(_ event: NoteEvent) -> Bool {
        guard let i = targets.firstIndex(where: { $0.status == .active }) else { return false }
        let midi = event.pitch.midi
        let t = event.compensatedTime
        if targets[i].expected.contains(midi) {
            targets[i].matched[midi] = 0
            targets[i].matchTimes[midi] = t
            // Chord notes must be played together: drop matches that are too old.
            for (m, mt) in targets[i].matchTimes where t - mt > chordWindow {
                targets[i].matchTimes[m] = nil
                targets[i].matched[m] = nil
            }
            if targets[i].remaining.isEmpty {
                let g: Grade
                switch targets[i].wrongAttempts {
                case 0: g = .perfect
                case 1: g = .good
                case 2: g = .ok
                default: g = .partial
                }
                finish(i, grade: g, score: g.value)
                activateNextWaitTarget()
            }
            return true
        }
        targets[i].wrongAttempts += 1
        wrongNotes += 1
        return false
    }

    private func activateNextWaitTarget() {
        if let next = targets.firstIndex(where: { $0.status != .done }) {
            targets[next].status = .active
        } else {
            complete()
        }
    }

    private func handleTimed(_ event: NoteEvent) -> Bool {
        let midi = event.pitch.midi
        let t = event.compensatedTime
        var bestIndex: Int?
        var bestError = TimeInterval.infinity
        for i in targets.indices where targets[i].status != .done && targets[i].remaining.contains(midi) {
            let err = t - time(ofBeat: targets[i].note.startBeat)
            if abs(err) <= windows.ok && abs(err) < abs(bestError) {
                bestError = err
                bestIndex = i
            }
        }
        guard let i = bestIndex else {
            wrongNotes += 1
            // Mark the nearest unfinished target so the UI can show where the slip happened.
            if let near = targets.indices.filter({ targets[$0].status != .done }).min(by: {
                abs(t - time(ofBeat: targets[$0].note.startBeat)) < abs(t - time(ofBeat: targets[$1].note.startBeat))
            }), abs(t - time(ofBeat: targets[near].note.startBeat)) <= windows.ok {
                targets[near].wrongAttempts += 1
            }
            return false
        }
        targets[i].matched[midi] = bestError
        targets[i].status = .active
        if targets[i].remaining.isEmpty {
            let grades = targets[i].matched.values.map { windows.grade(forError: $0) ?? .ok }
            let score = grades.map(\.value).reduce(0, +) / Double(grades.count)
            finish(i, grade: Grade.fromScore(score), score: score)
            checkTimedCompletion()
        }
        return true
    }

    /// Timed mode: finalizes targets whose window has passed. Call every frame / timer tick.
    public func tick(at time: TimeInterval) {
        guard mode == .timed, isRunning, !isPaused, !isFinished else { return }
        let nowBeat = beat(at: time)
        let okBeats = windows.ok / secondsPerBeat
        for i in targets.indices where targets[i].status != .done {
            let start = targets[i].note.startBeat
            if nowBeat > start + okBeats {
                if targets[i].matched.isEmpty {
                    finish(i, grade: .missed, score: 0)
                } else {
                    let fraction = Double(targets[i].matched.count) / Double(targets[i].expected.count)
                    let timing = targets[i].matched.values.map { (windows.grade(forError: $0) ?? .ok).value }.reduce(0, +) / Double(targets[i].matched.count)
                    finish(i, grade: .partial, score: fraction * timing * 0.8)
                }
            } else if nowBeat >= start - okBeats, targets[i].status == .upcoming {
                targets[i].status = .active
            }
        }
        checkTimedCompletion()
    }

    private func checkTimedCompletion() {
        if targets.allSatisfy({ $0.status == .done }) { complete() }
    }

    private func finish(_ i: Int, grade: Grade, score: Double) {
        targets[i].status = .done
        targets[i].grade = grade
        targets[i].score = score
    }

    private func complete() {
        isFinished = true
        isRunning = false
    }

    private func applyCapabilities() {
        for i in targets.indices where targets[i].status != .done {
            let full = Set(targets[i].note.pitches.map(\.midi))
            if capabilities.polyphonic || full.count == 1 {
                targets[i].expected = full
                targets[i].simplified = false
            } else {
                // Monophonic input (microphone): only the top (melody) note of a chord can be graded.
                targets[i].expected = [full.max()!]
                targets[i].simplified = true
            }
            let expected = targets[i].expected
            let keptMatches = targets[i].matched.filter { expected.contains($0.key) }
            let keptTimes = targets[i].matchTimes.filter { expected.contains($0.key) }
            targets[i].matched = keptMatches
            targets[i].matchTimes = keptTimes
        }
    }

    // MARK: Read-outs for the UI

    public var completedCount: Int { targets.filter { $0.status == .done }.count }
    public var progress: Double { targets.isEmpty ? 1 : Double(completedCount) / Double(targets.count) }

    /// Keys to highlight as "play these next".
    public func upcomingPitches(at time: TimeInterval, lookaheadBeats: Double = 0.75) -> Set<Int> {
        switch mode {
        case .waitForNotes:
            return targets.first(where: { $0.status == .active })?.remaining ?? []
        case .timed:
            let b = beat(at: time)
            var out = Set<Int>()
            for t in targets where t.status != .done && t.note.startBeat <= b + lookaheadBeats && t.note.startBeat >= b - windows.ok / secondsPerBeat {
                out.formUnion(t.remaining)
            }
            return out
        }
    }

    public var result: SessionResult {
        let total = targets.count
        let done = targets.filter { $0.status == .done }
        let scoreSum = done.reduce(0) { $0 + $1.score }
        var accuracy = total == 0 ? 1 : scoreSum / Double(total)
        if mode == .timed && total > 0 {
            accuracy *= Double(total) / (Double(total) + 0.5 * Double(wrongNotes))
        }
        let correct = done.filter { $0.grade != .missed && $0.grade != .partial }.count
        let played = done.filter { $0.grade != .missed }
        let timing: Double
        if mode == .waitForNotes {
            timing = 1
        } else if played.isEmpty {
            timing = 0
        } else {
            timing = played.map { t -> Double in
                let g = t.matched.values.map { (windows.grade(forError: $0) ?? .ok).value }
                return g.isEmpty ? 0 : g.reduce(0, +) / Double(g.count)
            }.reduce(0, +) / Double(played.count)
        }
        return SessionResult(
            accuracy: accuracy,
            noteAccuracy: total == 0 ? 1 : Double(correct) / Double(total),
            timingAccuracy: timing,
            correctTargets: correct,
            totalTargets: total,
            wrongNotes: wrongNotes,
            stars: SessionResult.stars(for: accuracy)
        )
    }
}

extension Grade {
    static func fromScore(_ s: Double) -> Grade {
        s >= 0.95 ? .perfect : s >= 0.8 ? .good : .ok
    }
}
