import Foundation

public struct Song: Identifiable, Equatable, Sendable {
    public var id: Int
    public var title: String
    /// Composer or "Traditional". Every song here is public domain.
    public var origin: String
    /// 1 = easiest.
    public var level: Int
    public var piece: Piece
    public var isPremium: Bool

    public var requiresPolyphony: Bool { piece.hasSimultaneousNotes }
}

/// Public-domain songs arranged for beginners.
public enum SongLibrary {
    public static let songs: [Song] = [
        song(101, "Twinkle, Twinkle, Little Star", "Traditional", 1, 92, right:
            "C4@1:q C4:q G4@4:q G4:q | A4@5:q A4:q G4@4:h | F4@3:q F4:q E4@2:q E4:q | D4@1:q D4:q C4@1:h | G4@5:q G4:q F4@4:q F4:q | E4@3:q E4:q D4@2:h | G4@5:q G4:q F4@4:q F4:q | E4@3:q E4:q D4@2:h | C4@1:q C4:q G4@4:q G4:q | A4@5:q A4:q G4@4:h | F4@3:q F4:q E4@2:q E4:q | D4@1:q D4:q C4@1:h"),
        song(102, "Mary Had a Little Lamb", "Traditional", 1, 100, right:
            "E4@3:q D4@2:q C4@1:q D4@2:q | E4@3:q E4:q E4:h | D4@2:q D4:q D4:h | E4@3:q G4@5:q G4:h | E4@3:q D4@2:q C4@1:q D4@2:q | E4@3:q E4:q E4:q E4:q | D4@2:q D4:q E4@3:q D4@2:q | C4@1:w"),
        song(103, "Ode to Joy", "Ludwig van Beethoven", 2, 100, right:
            "E4@3:q E4:q F4@4:q G4@5:q | G4:q F4@4:q E4@3:q D4@2:q | C4@1:q C4:q D4@2:q E4@3:q | E4:q. D4@2:e D4:h | E4@3:q E4:q F4@4:q G4@5:q | G4:q F4@4:q E4@3:q D4@2:q | C4@1:q C4:q D4@2:q E4@3:q | D4@2:q. C4@1:e C4:h | D4@2:q D4:q E4@3:q C4@1:q | D4@2:q E4@3:e F4@4:e E4@3:q C4@1:q | D4@2:q E4@3:e F4@4:e E4@3:q D4@2:q | C4@1:q D4@2:q G3@1:h | E4@3:q E4:q F4@4:q G4@5:q | G4:q F4@4:q E4@3:q D4@2:q | C4@1:q C4:q D4@2:q E4@3:q | D4@2:q. C4@1:e C4:h"),
        song(104, "Hot Cross Buns", "Traditional", 1, 100, right:
            "E4@3:q D4@2:q C4@1:h | E4@3:q D4@2:q C4@1:h | C4@1:e C4:e C4:e C4:e D4@2:e D4:e D4:e D4:e | E4@3:q D4@2:q C4@1:h"),
        song(105, "Frère Jacques", "Traditional", 1, 100, right:
            "C4@1:q D4@2:q E4@3:q C4@1:q | C4@1:q D4@2:q E4@3:q C4@1:q | E4@3:q F4@4:q G4@5:h | E4@3:q F4@4:q G4@5:h | G4@5:e A4:e G4:e F4@4:e E4@3:q C4@1:q | G4@5:e A4:e G4:e F4@4:e E4@3:q C4@1:q | C4@2:q G3@1:q C4@2:h | C4@2:q G3@1:q C4@2:h"),
        song(106, "London Bridge", "Traditional", 1, 100, right:
            "G4@5:q. A4:e G4@5:q F4@4:q | E4@3:q F4@4:q G4@5:h | D4@2:q E4@3:q F4@4:h | E4@3:q F4@4:q G4@5:h | G4@5:q. A4:e G4@5:q F4@4:q | E4@3:q F4@4:q G4@5:h | D4@2:h G4@5:h | E4@3:q C4@1:h."),
        song(107, "Row, Row, Row Your Boat", "Traditional", 1, 72, beatsPerBar: 3, right:
            "C4@1:q. C4:q. | C4:q D4@2:e E4@3:q. | E4:q D4@2:e E4@3:q F4@4:e | G4@5:h. | C5:e C5:e C5:e G4:e G4:e G4:e | E4@3:e E4:e E4:e C4@1:e C4:e C4:e | G4@5:q F4@4:e E4@3:q D4@2:e | C4@1:h.", premium: true),
        song(108, "Jingle Bells", "James Lord Pierpont", 2, 104, right:
            "E4@3:q E4:q E4:h | E4:q E4:q E4:h | E4@3:q G4@5:q C4@1:q. D4@2:e | E4@3:w | F4@4:q F4:q F4:q. F4:e | F4:q E4@3:q E4:q E4:e E4:e | E4:q D4@2:q D4:q E4@3:q | D4@2:h G4@5:h", premium: true),
        song(109, "When the Saints Go Marching In", "Traditional", 2, 104, right:
            "r:q C4@1:q E4@3:q F4@4:q | G4@5:w | r:q C4@1:q E4@3:q F4@4:q | G4@5:w | r:q C4@1:q E4@3:q F4@4:q | G4@5:h E4@3:h | C4@1:h E4@3:h | D4@2:w", premium: true),
        song(110, "Yankee Doodle", "Traditional", 2, 108, right:
            "C4@2:q C4:q D4@3:q E4@4:q | C4@2:q E4@4:q D4@3:h | C4@2:q C4:q D4@3:q E4@4:q | C4@2:h B3@1:h | C4@2:q C4:q D4@3:q E4@4:q | F4@5:q E4@4:q D4@3:q C4@2:q | B3@1:q G3:q A3:q B3:q | C4@2:h C4:h", premium: true),
        song(111, "Amazing Grace", "Traditional", 2, 84, beatsPerBar: 3, right:
            "r:h G3@1:q | C4@2:h E4@4:e C4@2:e | E4@4:h D4@3:q | C4@2:h A3@1:q | G3@1:h G3:q | C4@2:h E4@4:e C4@2:e | E4@4:h D4@3:e E4@4:e | G4@5:h.", premium: true),
        song(112, "Minuet in G", "Christian Petzold", 3, 100, beatsPerBar: 3, right:
            "D5@5:q G4@1:e A4@2:e B4@3:e C5@4:e | D5@5:q G4@1:q G4:q | E5@5:q C5@2:e D5@3:e E5@4:e F#5@5:e | G5@5:q G4@1:q G4:q | C5@4:q D5@5:e C5@4:e B4@3:e A4@2:e | B4@3:q C5@4:e B4@3:e A4@2:e G4@1:e | F#4@2:q G4@1:e A4@2:e B4@3:e G4@1:e | A4@2:h.", premium: true),
        song(113, "Twinkle, Twinkle (Two Hands)", "Traditional", 2, 84, right:
            "C4@1:q C4:q G4@4:q G4:q | A4@5:q A4:q G4@4:h | F4@3:q F4:q E4@2:q E4:q | D4@1:q D4:q C4@1:h", left:
            "C3@5:w | F3@2:h C3@5:h | F3@2:h C3@5:h | G2@5:h C3@1:h", premium: true),
        song(114, "Ode to Joy (Two Hands)", "Ludwig van Beethoven", 3, 88, right:
            "E4@3:q E4:q F4@4:q G4@5:q | G4:q F4@4:q E4@3:q D4@2:q | C4@1:q C4:q D4@2:q E4@3:q | E4:q. D4@2:e D4:h | E4@3:q E4:q F4@4:q G4@5:q | G4:q F4@4:q E4@3:q D4@2:q | C4@1:q C4:q D4@2:q E4@3:q | D4@2:q. C4@1:e C4:h", left:
            "C3@5:w | G2@5:w | C3@5:w | G2@5:h C3@1:h | C3@5:w | G2@5:w | C3@5:w | G2@5:h C3@1:h", premium: true),
    ]

    public static func song(id: Int) -> Song? { songs.first { $0.id == id } }

    static func song(_ id: Int, _ title: String, _ origin: String, _ level: Int, _ tempo: Double, beatsPerBar: Int = 4, right: String, left: String? = nil, premium: Bool = false) -> Song {
        Song(id: id, title: title, origin: origin, level: level,
             piece: Curriculum.piece(title, tempo, beatsPerBar: beatsPerBar, right: right, left: left),
             isPremium: premium)
    }
}

/// What MelodyPop Plus unlocks.
public enum Entitlements {
    public static let plusProductID = "com.saystudios.melodypop.plus"

    public static func isLessonLocked(_ id: Int, hasPlus: Bool) -> Bool {
        !hasPlus && id > Curriculum.freeLessonCount
    }

    public static func isSongLocked(_ song: Song, hasPlus: Bool) -> Bool {
        !hasPlus && song.isPremium
    }
}
