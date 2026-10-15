import Foundation

public enum Curriculum {
    public static let units: [CurriculumUnit] = [
        CurriculumUnit(id: 1, title: "Hello, Keyboard!", colorName: "lavender"),
    ]

    public static let lessons: [Lesson] = [
        Lesson(
            id: 1, unit: 1,
            title: "Meet Middle C",
            goal: "Find middle C and play it with your thumb.",
            tip: "Middle C is the white key just to the left of the two black keys near the middle of the piano. Put your right thumb (finger 1) on it and play each time it glows.",
            kind: .noteFinding, mode: .waitForNotes,
            piece: piece("Meet Middle C", 80, right: "C4@1:q C4@1:q C4@1:q C4@1:q | C4@1:q C4@1:q C4@1:h")
        ),
    ]

    public static func lesson(id: Int) -> Lesson? { lessons.first { $0.id == id } }

    static func piece(_ title: String, _ tempo: Double, beatsPerBar: Int = 4, right: String, left: String? = nil) -> Piece {
        do {
            return try Piece(title: title, tempo: tempo, beatsPerBar: beatsPerBar, right: right, left: left)
        } catch {
            fatalError("Curriculum notation error in \(title): \(error)")
        }
    }
}
