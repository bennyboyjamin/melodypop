import Foundation

/// One notated event: a single note or a chord, played by one hand.
public struct ScoreNote: Identifiable, Equatable, Codable, Sendable {
    public var id: Int
    public var pitches: [Pitch]
    public var startBeat: Double
    public var beats: Double
    public var hand: Hand
    public var finger: Int?

    public init(id: Int, pitches: [Pitch], startBeat: Double, beats: Double, hand: Hand, finger: Int? = nil) {
        self.id = id
        self.pitches = pitches.sorted()
        self.startBeat = startBeat
        self.beats = beats
        self.hand = hand
        self.finger = finger
    }

    public var isChord: Bool { pitches.count > 1 }
    public var endBeat: Double { startBeat + beats }
}

public struct Piece: Equatable, Codable, Sendable {
    public var title: String
    public var tempo: Double          // quarter-note beats per minute
    public var beatsPerBar: Int
    public var notes: [ScoreNote]
    /// Notes that are written but not graded (e.g. rests are implicit; this is for future accompaniment).
    public init(title: String, tempo: Double, beatsPerBar: Int = 4, notes: [ScoreNote]) {
        self.title = title
        self.tempo = tempo
        self.beatsPerBar = beatsPerBar
        self.notes = notes.sorted { ($0.startBeat, $0.pitches.first?.midi ?? 0) < ($1.startBeat, $1.pitches.first?.midi ?? 0) }
    }

    public var totalBeats: Double {
        let end = notes.map(\.endBeat).max() ?? 0
        let bar = Double(beatsPerBar)
        return (end / bar).rounded(.up) * bar
    }

    public var allPitches: [Pitch] { notes.flatMap(\.pitches) }
    public var lowest: Pitch? { allPitches.min() }
    public var highest: Pitch? { allPitches.max() }
    public var hasChords: Bool { notes.contains(where: \.isChord) }
    public var usesBothHands: Bool { Set(notes.map(\.hand)).count > 1 }
    /// True when two notes start together (a chord, or both hands at once).
    public var hasSimultaneousNotes: Bool {
        if hasChords { return true }
        let starts = notes.map(\.startBeat)
        return Set(starts).count != starts.count
    }

    /// Parses one or two hands written in MelodyPop's compact notation (see `Notation`).
    public init(title: String, tempo: Double, beatsPerBar: Int = 4, right: String, left: String? = nil) throws {
        var notes = try Notation.parse(right, hand: .right)
        if let left {
            let offset = (notes.map(\.id).max() ?? -1) + 1
            notes += try Notation.parse(left, hand: .left).map { var n = $0; n.id += offset; return n }
        }
        self.init(title: title, tempo: tempo, beatsPerBar: beatsPerBar, notes: notes)
    }
}

/// Compact text notation used to author lessons:
///
///     "C4:q D4:q E4:h | E4@3:q r:q C4+E4+G4:w"
///
/// * `PITCH:DURATION` — durations `w h q e s` (whole…sixteenth); a trailing `.` dots it (`h.`).
/// * `r:DURATION` — rest.
/// * `C4+E4+G4:h` — chord.
/// * `E4@3:q` — finger number 3.
/// * `|` bar lines are ignored (they're only for readability).
public enum Notation {
    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case badToken(String)
        case badPitch(String)
        case badDuration(String)
        public var description: String {
            switch self {
            case .badToken(let t): return "Bad token '\(t)'"
            case .badPitch(let t): return "Bad pitch '\(t)'"
            case .badDuration(let t): return "Bad duration '\(t)'"
            }
        }
    }

    public static func beats(for duration: Substring) throws -> Double {
        var d = duration
        var dotted = false
        if d.hasSuffix(".") { dotted = true; d = d.dropLast() }
        let base: Double
        switch d {
        case "w": base = 4
        case "h": base = 2
        case "q": base = 1
        case "e": base = 0.5
        case "s": base = 0.25
        default: throw ParseError.badDuration(String(duration))
        }
        return dotted ? base * 1.5 : base
    }

    public static func parse(_ text: String, hand: Hand) throws -> [ScoreNote] {
        var notes: [ScoreNote] = []
        var beat = 0.0
        for raw in text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }) {
            if raw == "|" { continue }
            let parts = raw.split(separator: ":")
            guard parts.count == 2 else { throw ParseError.badToken(String(raw)) }
            let length = try beats(for: parts[1])
            if parts[0] == "r" { beat += length; continue }
            var pitchPart = parts[0]
            var finger: Int?
            if let at = pitchPart.firstIndex(of: "@") {
                finger = Int(pitchPart[pitchPart.index(after: at)...])
                pitchPart = pitchPart[..<at]
            }
            var pitches: [Pitch] = []
            for name in pitchPart.split(separator: "+") {
                guard let p = Pitch(name: String(name)) else { throw ParseError.badPitch(String(name)) }
                pitches.append(p)
            }
            notes.append(ScoreNote(id: notes.count, pitches: pitches, startBeat: beat, beats: length, hand: hand, finger: finger))
            beat += length
        }
        return notes
    }
}
