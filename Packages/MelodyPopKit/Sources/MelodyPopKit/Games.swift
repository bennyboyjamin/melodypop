import Foundation

/// Rules for the Piano Games. All games consume normalized `NoteEvent`s, so they work in
/// every play mode (they only need one note at a time, so the microphone works too).
public enum PianoGame: String, CaseIterable, Identifiable, Sendable {
    case noteCatcher   // read a note on the staff, play it
    case keyFinder     // find any key with a given letter name
    case melodyMemory  // listen, then play the tune back (grows each round)

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .noteCatcher: return "Note Catcher"
        case .keyFinder: return "Key Finder"
        case .melodyMemory: return "Melody Memory"
        }
    }

    public var blurb: String {
        switch self {
        case .noteCatcher: return "A note pops onto the staff — play it before the timer runs out!"
        case .keyFinder: return "Find the key with that letter name. Any octave counts!"
        case .melodyMemory: return "Pip plays a tune. Play it back — it grows one note longer each round."
        }
    }

    public var symbol: String {
        switch self {
        case .noteCatcher: return "music.note"
        case .keyFinder: return "magnifyingglass"
        case .melodyMemory: return "brain.head.profile"
        }
    }

    /// Stable id used when logging plays.
    public var logID: Int {
        switch self {
        case .noteCatcher: return 201
        case .keyFinder: return 202
        case .melodyMemory: return 203
        }
    }
}

/// Note Catcher and Key Finder: a fixed number of timed rounds.
public struct NoteQuiz: Sendable {
    public enum Kind: Sendable { case exactPitch, letterName }

    public struct Round: Equatable, Sendable {
        public var target: Pitch
        public var answered = false
        public var correct = false
        public var attempts = 0
        public var responseTime: TimeInterval?
    }

    public let kind: Kind
    public let timeLimit: TimeInterval
    public private(set) var rounds: [Round]
    public private(set) var index = 0
    private var roundStart: TimeInterval = 0

    /// `pool` is the set of pitches the quiz may ask for (lesson-appropriate range).
    public init<G: RandomNumberGenerator>(kind: Kind, pool: [Pitch], count: Int = 10, timeLimit: TimeInterval = 6, generator: inout G) {
        precondition(!pool.isEmpty)
        self.kind = kind
        self.timeLimit = timeLimit
        var picked: [Pitch] = []
        for _ in 0..<count {
            var p = pool.randomElement(using: &generator)!
            // Never ask for the same note twice in a row.
            if pool.count > 1 { while p == picked.last { p = pool.randomElement(using: &generator)! } }
            picked.append(p)
        }
        rounds = picked.map { Round(target: $0) }
    }

    public var isFinished: Bool { index >= rounds.count }
    public var current: Round? { isFinished ? nil : rounds[index] }

    public mutating func beginRound(at time: TimeInterval) { roundStart = time }

    public func timeLeft(at time: TimeInterval) -> TimeInterval { max(0, timeLimit - (time - roundStart)) }

    public func matches(_ pitch: Pitch) -> Bool {
        guard let target = current?.target else { return false }
        switch kind {
        case .exactPitch: return pitch == target
        case .letterName: return pitch.pitchClass == target.pitchClass
        }
    }

    /// Returns true when the round was answered correctly (and the quiz advances).
    @discardableResult
    public mutating func answer(_ pitch: Pitch, at time: TimeInterval) -> Bool {
        guard !isFinished else { return false }
        rounds[index].attempts += 1
        if matches(pitch) {
            rounds[index].answered = true
            rounds[index].correct = true
            rounds[index].responseTime = time - roundStart
            index += 1
            return true
        }
        return false
    }

    /// Ends the round as missed when time runs out. Returns true if it timed out.
    @discardableResult
    public mutating func checkTimeout(at time: TimeInterval) -> Bool {
        guard !isFinished, time - roundStart >= timeLimit else { return false }
        rounds[index].answered = true
        index += 1
        return true
    }

    /// Points: 100 per correct answer, up to +50 for speed, −10 per wrong attempt.
    public var score: Int {
        rounds.reduce(0) { total, r in
            guard r.correct, let t = r.responseTime else { return total }
            let speed = Int(50 * max(0, 1 - t / timeLimit))
            return total + 100 + speed - 10 * max(0, r.attempts - 1)
        }
    }

    public var correctCount: Int { rounds.filter(\.correct).count }
    public var accuracy: Double { rounds.isEmpty ? 0 : Double(correctCount) / Double(rounds.count) }
}

/// Melody Memory ("Simon"): the sequence grows by one note each round; a mistake ends the game.
public struct MelodyMemory: Sendable {
    public private(set) var sequence: [Pitch] = []
    public private(set) var position = 0
    public private(set) var isOver = false
    public private(set) var bestLength = 0
    public let pool: [Pitch]

    public init(pool: [Pitch]) {
        precondition(!pool.isEmpty)
        self.pool = pool
    }

    /// Adds a note and resets the player's position. Call before playing the tune.
    public mutating func nextRound<G: RandomNumberGenerator>(using g: inout G) {
        var p = pool.randomElement(using: &g)!
        if pool.count > 1 { while p == sequence.last { p = pool.randomElement(using: &g)! } }
        sequence.append(p)
        position = 0
    }

    public enum Result: Equatable, Sendable { case correct, roundComplete, wrong, ignored }

    public mutating func play(_ pitch: Pitch) -> Result {
        guard !isOver, position < sequence.count else { return .ignored }
        if pitch == sequence[position] {
            position += 1
            if position == sequence.count {
                bestLength = max(bestLength, sequence.count)
                return .roundComplete
            }
            return .correct
        }
        isOver = true
        return .wrong
    }

    public var score: Int { bestLength * 50 }
}
