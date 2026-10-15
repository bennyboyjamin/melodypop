import Foundation

/// The beginner curriculum: 5 units × 6 lessons.
public enum Curriculum {
    public static let units: [CurriculumUnit] = [
        CurriculumUnit(id: 1, title: "Hello, Keyboard!", colorName: "lavender"),
        CurriculumUnit(id: 2, title: "Feel the Beat", colorName: "mint"),
        CurriculumUnit(id: 3, title: "Melody Makers", colorName: "peach"),
        CurriculumUnit(id: 4, title: "Scales & Steps", colorName: "lavender"),
        CurriculumUnit(id: 5, title: "Two-Hand Heroes", colorName: "mint"),
    ]

    /// Lessons 1–10 are free; the rest come with MelodyPop Plus.
    public static let freeLessonCount = 10

    public static let lessons: [Lesson] = unit1 + unit2 + unit3 + unit4 + unit5

    public static func lesson(id: Int) -> Lesson? { lessons.first { $0.id == id } }

    // MARK: Unit 1 — note recognition (wait mode: the lesson waits for each note)

    static let unit1: [Lesson] = [
        Lesson(
            id: 1, unit: 1,
            title: "Meet Middle C",
            goal: "Find middle C and play it with your thumb.",
            tip: "Middle C is the white key just to the left of the two black keys near the middle of the piano. Put your right thumb (finger 1) on it and play each time it glows.",
            kind: .noteFinding, mode: .waitForNotes,
            piece: piece("Meet Middle C", 80, right: "C4@1:q C4@1:q C4@1:q C4@1:q | C4@1:q C4@1:q C4@1:h")
        ),
        Lesson(
            id: 2, unit: 1,
            title: "D and E Are Neighbours",
            goal: "Walk from C to D to E with fingers 1, 2 and 3.",
            tip: "D lives between the two black keys. E is just to the right of them. Keep your fingers curved like you're holding a bubble.",
            kind: .noteFinding, mode: .waitForNotes,
            piece: piece("C D E", 80, right: "C4@1:q D4@2:q E4@3:q D4@2:q | C4@1:q D4@2:q E4@3:h | E4@3:q D4@2:q C4@1:h")
        ),
        Lesson(
            id: 3, unit: 1,
            title: "Black Key Twins and Triplets",
            goal: "Find the groups of two and three black keys.",
            tip: "Black keys come in groups of 2 and 3. That pattern repeats all the way up the piano — it's your map! Their names are sharps, like C♯ (C-sharp).",
            kind: .noteFinding, mode: .waitForNotes,
            piece: piece("Black Keys", 80, right: "C#4@2:q D#4@3:q C#4@2:q D#4@3:q | F#4@2:q G#4@3:q A#4@4:h | C#4@2:q D#4@3:q F#4@2:q G#4@3:q | A#4@4:w")
        ),
        Lesson(
            id: 4, unit: 1,
            title: "F and G",
            goal: "Add F (finger 4) and G (finger 5).",
            tip: "F is just left of the three black keys. G is next door. Now your whole hand has a key to play!",
            kind: .noteFinding, mode: .waitForNotes,
            piece: piece("F and G", 80, right: "F4@4:q G4@5:q F4@4:q G4@5:q | E4@3:q F4@4:q G4@5:h | C4@1:q D4@2:q E4@3:q F4@4:q | G4@5:w")
        ),
        Lesson(
            id: 5, unit: 1,
            title: "Five-Finger C Position",
            goal: "Play C D E F G up and down — one finger per key.",
            tip: "Thumb on C, then each finger gets its own key. Look at the finger numbers above the notes.",
            kind: .noteFinding, mode: .waitForNotes,
            piece: piece("C Position", 80, right: "C4@1:q D4@2:q E4@3:q F4@4:q | G4@5:w | G4@5:q F4@4:q E4@3:q D4@2:q | C4@1:w")
        ),
        Lesson(
            id: 6, unit: 1,
            title: "Hello, Left Hand",
            goal: "Play C position with your left hand.",
            tip: "Your left pinky (finger 5) goes on the C below middle C. Left-hand notes are written on the bass staff (the one with the 𝄢 clef).",
            kind: .noteFinding, mode: .waitForNotes,
            piece: piece("Left Hand C", 80, right: "", left: "C3@5:q D3@4:q E3@3:q F3@2:q | G3@1:w | G3@1:q F3@2:q E3@3:q D3@4:q | C3@5:w")
        ),
    ]

    // MARK: Unit 2 — rhythm (timed: play on the beat)

    static let unit2: [Lesson] = [
        Lesson(
            id: 7, unit: 2,
            title: "Quarter-Note March",
            goal: "Play one note on every beat.",
            tip: "A quarter note gets one beat. Listen to the count-in, then march along: 1, 2, 3, 4!",
            kind: .rhythm, mode: .timed,
            piece: piece("Quarter March", 72, right: "C4@1:q C4:q C4:q C4:q | C4:q C4:q C4:q C4:q | E4@3:q E4:q E4:q E4:q | C4@1:q C4:q C4:h")
        ),
        Lesson(
            id: 8, unit: 2,
            title: "Hold On, Half Notes",
            goal: "Half notes last two beats.",
            tip: "A half note is a hollow note with a stem. Play it, then keep counting \"2\" before moving on.",
            kind: .rhythm, mode: .timed,
            piece: piece("Half Notes", 76, right: "C4@1:h D4@2:h | E4@3:q E4:q E4:h | D4@2:h C4@1:h | E4@3:q D4@2:q C4@1:h")
        ),
        Lesson(
            id: 9, unit: 2,
            title: "Whole Notes and Rests",
            goal: "Whole notes last four beats; rests are silent beats.",
            tip: "A whole note is a hollow note with no stem — count all the way to 4. When there's a gap in the music, that's a rest: stay quiet!",
            kind: .rhythm, mode: .timed,
            piece: piece("Wholes and Rests", 76, right: "C4@1:w | E4@3:q r:q E4:q r:q | G4@5:w | E4@3:q r:q C4@1:h")
        ),
        Lesson(
            id: 10, unit: 2,
            title: "Counting to Three",
            goal: "Play in 3/4 time with a dotted half note.",
            tip: "Some music counts in threes, like a waltz: ONE two three. A dot after a half note adds one more beat — three beats in all.",
            kind: .rhythm, mode: .timed,
            piece: piece("Waltz Time", 84, beatsPerBar: 3, right: "C4@1:h. | E4@3:q E4:q E4:q | G4@5:h E4@3:q | C4@1:h.")
        ),
        Lesson(
            id: 11, unit: 2,
            title: "Eighth-Note Hop",
            goal: "Two eighth notes fit in one beat.",
            tip: "Eighth notes have a little flag. Say \"ti-ti\" for two eighths and \"ta\" for a quarter.",
            kind: .rhythm, mode: .timed,
            piece: piece("Eighth Hop", 72, right: "C4@1:e C4:e D4@2:e D4:e E4@3:q E4:q | E4:e E4:e D4:e D4:e C4@1:h | C4:e D4:e E4:e F4@4:e G4@5:q G4:q | G4:e F4:e E4:e D4:e C4:h")
        ),
        Lesson(
            id: 12, unit: 2,
            title: "Rhythm Remix",
            goal: "Mix quarters, eighths, halves and rests.",
            tip: "You know every note length now! Clap the rhythm once before you play it.",
            kind: .rhythm, mode: .timed,
            piece: piece("Rhythm Remix", 80, right: "C4@1:q E4@3:e E4:e G4@5:q E4:q | F4@4:h D4@2:q r:q | E4@3:e D4@2:e C4@1:e D4:e E4:q E4:q | C4@1:w")
        ),
    ]

    // MARK: Unit 3 — melodies

    static let unit3: [Lesson] = [
        Lesson(
            id: 13, unit: 3,
            title: "Hot Cross Buns",
            goal: "Your first real song, in C position.",
            tip: "This song only uses E, D and C — fingers 3, 2 and 1. Take your time; MelodyPop waits for you.",
            kind: .melody, mode: .waitForNotes,
            piece: piece("Hot Cross Buns", 92, right: "E4@3:q D4@2:q C4@1:h | E4@3:q D4@2:q C4@1:h | C4@1:e C4:e C4:e C4:e D4@2:e D4:e D4:e D4:e | E4@3:q D4@2:q C4@1:h")
        ),
        Lesson(
            id: 14, unit: 3,
            title: "Mary Had a Little Lamb",
            goal: "Play a whole song in time.",
            tip: "Watch the playhead glide across the music and play each note as it reaches the line.",
            kind: .melody, mode: .timed,
            piece: piece("Mary Had a Little Lamb", 92, right: "E4@3:q D4@2:q C4@1:q D4@2:q | E4@3:q E4:q E4:h | D4@2:q D4:q D4:h | E4@3:q G4@5:q G4:h | E4@3:q D4@2:q C4@1:q D4@2:q | E4@3:q E4:q E4:q E4:q | D4@2:q D4:q E4@3:q D4@2:q | C4@1:w")
        ),
        Lesson(
            id: 15, unit: 3,
            title: "Twinkle, Twinkle",
            goal: "Stretch to A with your pinky.",
            tip: "Start with your thumb on C. When the music jumps to G and A, slide your hand so finger 4 is on G and 5 is on A.",
            kind: .melody, mode: .timed,
            piece: piece("Twinkle, Twinkle", 90, right: "C4@1:q C4:q G4@4:q G4:q | A4@5:q A4:q G4@4:h | F4@3:q F4:q E4@2:q E4:q | D4@1:q D4:q C4@1:h")
        ),
        Lesson(
            id: 16, unit: 3,
            title: "Ode to Joy",
            goal: "Beethoven's famous tune, with a dotted rhythm.",
            tip: "A dotted quarter is one and a half beats, so the eighth note after it comes a little late. Listen to the demo first!",
            kind: .melody, mode: .timed,
            piece: piece("Ode to Joy", 96, right: "E4@3:q E4:q F4@4:q G4@5:q | G4:q F4@4:q E4@3:q D4@2:q | C4@1:q C4:q D4@2:q E4@3:q | E4:q. D4@2:e D4:h | E4@3:q E4:q F4@4:q G4@5:q | G4:q F4@4:q E4@3:q D4@2:q | C4@1:q C4:q D4@2:q E4@3:q | D4@2:q. C4@1:e C4:h")
        ),
        Lesson(
            id: 17, unit: 3,
            title: "Au Clair de la Lune",
            goal: "A gentle French song by moonlight.",
            tip: "Keep your wrist relaxed and let each note ring for its full length.",
            kind: .melody, mode: .timed,
            piece: piece("Au Clair de la Lune", 88, right: "C4@1:q C4:q C4:q D4@2:q | E4@3:h D4@2:h | C4@1:q E4@3:q D4@2:q D4:q | C4@1:w | C4@1:q C4:q C4:q D4@2:q | E4@3:h D4@2:h | C4@1:q E4@3:q D4@2:q D4:q | C4@1:w")
        ),
        Lesson(
            id: 18, unit: 3,
            title: "Lightly Row",
            goal: "Skip between notes, not just step.",
            tip: "G to E skips over F. Skips look like jumps of two lines (or two spaces) on the staff.",
            kind: .melody, mode: .timed,
            piece: piece("Lightly Row", 96, right: "G4@5:q E4@3:q E4:h | F4@4:q D4@2:q D4:h | C4@1:q D4@2:q E4@3:q F4@4:q | G4@5:q G4:q G4:h | G4@5:q E4@3:q E4:q E4:q | F4@4:q D4@2:q D4:q D4:q | C4@1:q E4@3:q G4@5:q G4:q | C4@1:w")
        ),
    ]

    // MARK: Unit 4 — scales

    static let unit4: [Lesson] = [
        Lesson(
            id: 19, unit: 4,
            title: "C Major Scale Up",
            goal: "Eight notes up, with a thumb tuck.",
            tip: "After E (finger 3), tuck your thumb under to play F. Then fingers 2, 3, 4, 5 finish the climb to high C.",
            kind: .scale, mode: .waitForNotes,
            piece: piece("C Scale Up", 80, right: "C4@1:q D4@2:q E4@3:q F4@1:q | G4@2:q A4@3:q B4@4:q C5@5:q")
        ),
        Lesson(
            id: 20, unit: 4,
            title: "C Major Scale Down",
            goal: "Come back down, crossing finger 3 over your thumb.",
            tip: "Going down, after F (thumb), cross finger 3 over to E.",
            kind: .scale, mode: .waitForNotes,
            piece: piece("C Scale Down", 80, right: "C5@5:q B4@4:q A4@3:q G4@2:q | F4@1:q E4@3:q D4@2:q C4@1:q")
        ),
        Lesson(
            id: 21, unit: 4,
            title: "Scale in Time",
            goal: "Up and down the C scale with a steady beat.",
            tip: "Smooth and even, like walking up and down stairs.",
            kind: .scale, mode: .timed,
            piece: piece("C Scale in Time", 80, right: "C4@1:q D4@2:q E4@3:q F4@1:q | G4@2:q A4@3:q B4@4:q C5@5:q | B4@4:q A4@3:q G4@2:q F4@1:q | E4@3:q D4@2:q C4@1:h")
        ),
        Lesson(
            id: 22, unit: 4,
            title: "G Major Scale",
            goal: "A new scale with one black key: F♯.",
            tip: "Start on G with your thumb. Every note is white except F♯ — the black key just right of F.",
            kind: .scale, mode: .waitForNotes,
            piece: piece("G Scale", 80, right: "G4@1:q A4@2:q B4@3:q C5@1:q | D5@2:q E5@3:q F#5@4:q G5@5:q | F#5@4:q E5@3:q D5@2:q C5@1:q | B4@3:q A4@2:q G4@1:h")
        ),
        Lesson(
            id: 23, unit: 4,
            title: "Left-Hand C Scale",
            goal: "The C scale with your left hand.",
            tip: "Left hand starts with the pinky on C. After G (thumb), cross finger 3 over to play A.",
            kind: .scale, mode: .waitForNotes,
            piece: piece("LH C Scale", 80, right: "", left: "C3@5:q D3@4:q E3@3:q F3@2:q | G3@1:q A3@3:q B3@2:q C4@1:q")
        ),
        Lesson(
            id: 24, unit: 4,
            title: "Steps and Skips",
            goal: "Read whether notes step or skip.",
            tip: "A step moves from a line to the next space. A skip jumps from line to line (or space to space).",
            kind: .melody, mode: .timed,
            piece: piece("Steps and Skips", 88, right: "C4@1:q E4@3:q D4@2:q F4@4:q | E4@3:q G4@5:q G4:h | G4@5:q E4@3:q F4@4:q D4@2:q | E4@3:q C4@1:q C4:h")
        ),
    ]

    // MARK: Unit 5 — two-hand coordination

    static let unit5: [Lesson] = [
        Lesson(
            id: 25, unit: 5,
            title: "Hands Take Turns",
            goal: "Left hand, then right hand, back and forth.",
            tip: "Only one hand plays at a time, so you can use the microphone for this one too.",
            kind: .twoHands, mode: .timed,
            piece: piece("Taking Turns", 80, right: "r:h E4@3:h | r:h F4@4:h | r:h G4@5:h | r:h C4@1:h", left: "C3@5:h r:h | D3@4:h r:h | E3@3:h r:h | C3@5:h r:h")
        ),
        Lesson(
            id: 26, unit: 5,
            title: "Your First Chord",
            goal: "Play C, E and G together: the C major chord.",
            tip: "Fingers 1, 3 and 5 press down at exactly the same time. Chords need Connect My Keyboard or Play on Screen.",
            kind: .chords, mode: .waitForNotes,
            piece: piece("C Chord", 72, right: "C4@1+E4@3+G4@5:w | C4+E4+G4:w | C4+E4+G4:h C4+E4+G4:h | C4+E4+G4:w")
        ),
        Lesson(
            id: 27, unit: 5,
            title: "Bass Note + Melody",
            goal: "Hold a left-hand note while the right hand plays.",
            tip: "Press the low C with your left pinky and keep holding while your right hand plays Hot Cross Buns.",
            kind: .twoHands, mode: .timed,
            piece: piece("Bass and Melody", 80, right: "E4@3:q D4@2:q C4@1:h | E4@3:q D4@2:q C4@1:h", left: "C3@5:w | C3@5:w")
        ),
        Lesson(
            id: 28, unit: 5,
            title: "C, F and G Chords",
            goal: "Move between three chords without looking away.",
            tip: "From C chord, keep your thumb on C and move fingers up for F (C-F-A). For G, move your hand to B-D-G.",
            kind: .chords, mode: .waitForNotes,
            piece: piece("C F G", 72, right: "C4@1+E4+G4:w | C4@1+F4+A4:w | B3@1+D4+G4:w | C4@1+E4+G4:w")
        ),
        Lesson(
            id: 29, unit: 5,
            title: "Ode to Joy, Two Hands",
            goal: "Melody in the right hand, bass notes in the left.",
            tip: "Practise slowly with the speed menu first, then try full speed.",
            kind: .twoHands, mode: .timed,
            piece: piece("Ode to Joy (Two Hands)", 84, right: "E4@3:q E4:q F4@4:q G4@5:q | G4:q F4@4:q E4@3:q D4@2:q | C4@1:q C4:q D4@2:q E4@3:q | E4:q. D4@2:e D4:h", left: "C3@5:w | G2@5:w | C3@5:w | G2@5:h C3@1:h")
        ),
        Lesson(
            id: 30, unit: 5,
            title: "Twinkle Finale",
            goal: "Your big performance — both hands!",
            tip: "You've learned so much! Listen once, then play it for someone you love.",
            kind: .twoHands, mode: .timed,
            piece: piece("Twinkle (Two Hands)", 84, right: "C4@1:q C4:q G4@4:q G4:q | A4@5:q A4:q G4@4:h | F4@3:q F4:q E4@2:q E4:q | D4@1:q D4:q C4@1:h", left: "C3@5:w | F3@2:h C3@5:h | F3@2:h C3@5:h | G2@5:h C3@1:h")
        ),
    ]

    static func piece(_ title: String, _ tempo: Double, beatsPerBar: Int = 4, right: String, left: String? = nil) -> Piece {
        do {
            return try Piece(title: title, tempo: tempo, beatsPerBar: beatsPerBar, right: right, left: left)
        } catch {
            fatalError("Curriculum notation error in \(title): \(error)")
        }
    }
}
