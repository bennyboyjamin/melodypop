import Foundation

/// A piano pitch identified by its MIDI note number (A0 = 21, middle C = 60, C8 = 108).
public struct Pitch: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let midi: Int

    public init(_ midi: Int) { self.midi = midi }

    public static let lowestPianoKey = Pitch(21)
    public static let highestPianoKey = Pitch(108)
    public static let middleC = Pitch(60)
    public static let pianoRange: ClosedRange<Int> = 21...108

    public static func < (lhs: Pitch, rhs: Pitch) -> Bool { lhs.midi < rhs.midi }

    static let sharpNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    static let solfege = ["Do", "Do♯", "Re", "Re♯", "Mi", "Fa", "Fa♯", "Sol", "Sol♯", "La", "La♯", "Ti"]
    /// Pitch class (0 = C ... 11 = B) → diatonic letter index (C=0 ... B=6) when spelled with sharps.
    static let letterIndex = [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6]

    public var pitchClass: Int { ((midi % 12) + 12) % 12 }
    public var octave: Int { midi / 12 - 1 }
    public var isBlackKey: Bool { [1, 3, 6, 8, 10].contains(pitchClass) }
    public var isSharp: Bool { isBlackKey }

    /// Letter name without octave, e.g. "C♯".
    public var name: String { Pitch.sharpNames[pitchClass] }
    /// Scientific pitch name, e.g. "C4".
    public var fullName: String { "\(name)\(octave)" }
    public var solfegeName: String { Pitch.solfege[pitchClass] }
    public var description: String { fullName }

    /// Diatonic staff position: number of letter steps above C0 (C0 = 0, D0 = 1 ... C4 = 28).
    public var diatonicStep: Int { octave * 7 + Pitch.letterIndex[pitchClass] }

    /// Equal-tempered frequency with A4 = 440 Hz.
    public var frequency: Double { Pitch.frequency(ofMIDI: Double(midi)) }

    public static func frequency(ofMIDI m: Double, a4: Double = 440) -> Double {
        a4 * pow(2, (m - 69) / 12)
    }

    /// Fractional MIDI number for a frequency (69.0 = A4).
    public static func midiValue(forFrequency f: Double, a4: Double = 440) -> Double {
        69 + 12 * log2(f / a4)
    }

    /// Parses names like "C4", "F#3", "Bb2", "C♯5".
    public init?(name raw: String) {
        let s = raw.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "♯", with: "#")
            .replacingOccurrences(of: "♭", with: "b")
        guard let first = s.first, let base = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11][String(first).uppercased()] else { return nil }
        var rest = s.dropFirst()
        var accidental = 0
        while let c = rest.first, c == "#" || c == "b" {
            accidental += (c == "#") ? 1 : -1
            rest = rest.dropFirst()
        }
        guard let octave = Int(rest) else { return nil }
        self.midi = (octave + 1) * 12 + base + accidental
    }
}

public enum Hand: String, Codable, Sendable, CaseIterable {
    case left, right
}
