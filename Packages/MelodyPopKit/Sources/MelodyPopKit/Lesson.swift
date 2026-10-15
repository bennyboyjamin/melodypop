import Foundation

public enum LessonKind: String, Codable, Sendable, CaseIterable {
    case noteFinding, rhythm, melody, scale, twoHands, chords

    public var label: String {
        switch self {
        case .noteFinding: return "Notes"
        case .rhythm: return "Rhythm"
        case .melody: return "Melody"
        case .scale: return "Scales"
        case .twoHands: return "Two Hands"
        case .chords: return "Chords"
        }
    }

    public var symbol: String {
        switch self {
        case .noteFinding: return "pianokeys"
        case .rhythm: return "metronome"
        case .melody: return "music.note"
        case .scale: return "stairs"
        case .twoHands: return "hands.clap"
        case .chords: return "music.quarternote.3"
        }
    }
}

public struct Lesson: Identifiable, Equatable, Sendable {
    public var id: Int
    public var unit: Int
    public var title: String
    /// One line shown on the journey map.
    public var goal: String
    /// Short teaching text shown before playing.
    public var tip: String
    public var kind: LessonKind
    public var mode: EvaluationMode
    public var piece: Piece
    public var passAccuracy: Double
    public var showFingers: Bool

    public init(id: Int, unit: Int, title: String, goal: String, tip: String, kind: LessonKind, mode: EvaluationMode, piece: Piece, passAccuracy: Double = 0.7, showFingers: Bool = true) {
        self.id = id
        self.unit = unit
        self.title = title
        self.goal = goal
        self.tip = tip
        self.kind = kind
        self.mode = mode
        self.piece = piece
        self.passAccuracy = passAccuracy
        self.showFingers = showFingers
    }

    /// Chords or both hands together need an input that can hear several notes at once.
    public var requiresPolyphony: Bool { piece.hasSimultaneousNotes }

    public func isAvailable(for source: InputSource) -> Bool {
        !requiresPolyphony || source.capabilities.polyphonic
    }

    public func unavailableReason(for source: InputSource) -> String? {
        guard !isAvailable(for: source) else { return nil }
        return "This lesson has notes played together. The microphone can only hear one piano note at a time reliably, so use Connect My Keyboard or Play on Screen for it."
    }
}

public struct CurriculumUnit: Identifiable, Equatable, Sendable {
    public var id: Int
    public var title: String
    public var colorName: String
}
