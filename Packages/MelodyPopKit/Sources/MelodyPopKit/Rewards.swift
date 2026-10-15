import Foundation

public struct StickerDefinition: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let symbol: String
    public let colorName: String
}

/// Everything reward rules need to know about a student, computed from saved progress.
public struct ProgressSnapshot: Equatable, Sendable {
    public var completedLessons: Set<Int> = []
    public var threeStarLessons: Int = 0
    public var totalStars: Int = 0
    public var practiceDays: [Date] = []
    public var songsCompleted: Int = 0
    public var gamesPlayed: Int = 0
    public var perfectRuns: Int = 0
    public var recordings: Int = 0
    public var minutesPracticed: Double = 0
    public var sourcesUsed: Set<InputSource> = []
    public var bestGameScore: Int = 0

    public init() {}
}

public enum RewardRules {
    public static let all: [StickerDefinition] = [
        .init(id: "first-note", title: "First Note", detail: "Finish your first lesson", symbol: "music.note", colorName: "lavender"),
        .init(id: "perfect", title: "Perfect Pop", detail: "Score 100% on anything", symbol: "sparkles", colorName: "peach"),
        .init(id: "unit-1", title: "Keyboard Explorer", detail: "Finish Unit 1", symbol: "map.fill", colorName: "mint"),
        .init(id: "unit-2", title: "Rhythm Rocket", detail: "Finish Unit 2", symbol: "metronome.fill", colorName: "lavender"),
        .init(id: "unit-3", title: "Melody Maker", detail: "Finish Unit 3", symbol: "music.quarternote.3", colorName: "peach"),
        .init(id: "unit-4", title: "Scale Climber", detail: "Finish Unit 4", symbol: "stairs", colorName: "mint"),
        .init(id: "unit-5", title: "Two-Hand Hero", detail: "Finish Unit 5", symbol: "hands.clap.fill", colorName: "lavender"),
        .init(id: "stars-25", title: "Star Collector", detail: "Earn 25 stars", symbol: "star.fill", colorName: "peach"),
        .init(id: "stars-60", title: "Superstar", detail: "Earn 60 stars", symbol: "star.circle.fill", colorName: "mint"),
        .init(id: "streak-3", title: "Three-Day Streak", detail: "Practise 3 days in a row", symbol: "flame.fill", colorName: "peach"),
        .init(id: "streak-7", title: "Week of Music", detail: "Practise 7 days in a row", symbol: "calendar", colorName: "lavender"),
        .init(id: "first-song", title: "Song Bird", detail: "Finish a song", symbol: "bird.fill", colorName: "mint"),
        .init(id: "songs-5", title: "Concert Ready", detail: "Finish 5 songs", symbol: "music.mic", colorName: "lavender"),
        .init(id: "gamer", title: "Game Time", detail: "Play 5 piano games", symbol: "gamecontroller.fill", colorName: "peach"),
        .init(id: "composer", title: "Little Composer", detail: "Save a recording", symbol: "record.circle", colorName: "mint"),
        .init(id: "all-modes", title: "Mode Master", detail: "Practise with all three play modes", symbol: "rectangle.3.group.fill", colorName: "lavender"),
        .init(id: "minutes-60", title: "Hour of Practice", detail: "Practise for 60 minutes in total", symbol: "clock.fill", colorName: "peach"),
    ]

    /// Lessons per unit (5 units × 6 lessons).
    public static func lessons(inUnit unit: Int) -> ClosedRange<Int> { ((unit - 1) * 6 + 1)...(unit * 6) }

    public static func earned(_ s: ProgressSnapshot, today: Date = .now, calendar: Calendar = .current) -> Set<String> {
        var out = Set<String>()
        if !s.completedLessons.isEmpty { out.insert("first-note") }
        if s.perfectRuns > 0 { out.insert("perfect") }
        for unit in 1...5 where lessons(inUnit: unit).allSatisfy({ s.completedLessons.contains($0) }) {
            out.insert("unit-\(unit)")
        }
        if s.totalStars >= 25 { out.insert("stars-25") }
        if s.totalStars >= 60 { out.insert("stars-60") }
        let streak = longestStreak(days: s.practiceDays, calendar: calendar)
        if streak >= 3 { out.insert("streak-3") }
        if streak >= 7 { out.insert("streak-7") }
        if s.songsCompleted >= 1 { out.insert("first-song") }
        if s.songsCompleted >= 5 { out.insert("songs-5") }
        if s.gamesPlayed >= 5 { out.insert("gamer") }
        if s.recordings >= 1 { out.insert("composer") }
        if s.sourcesUsed.count == InputSource.allCases.count { out.insert("all-modes") }
        if s.minutesPracticed >= 60 { out.insert("minutes-60") }
        return out
    }

    /// Consecutive days, counting back from today (or yesterday, so the streak survives until bedtime).
    public static func currentStreak(days: [Date], today: Date = .now, calendar: Calendar = .current) -> Int {
        let set = Set(days.map { calendar.startOfDay(for: $0) })
        var day = calendar.startOfDay(for: today)
        if !set.contains(day) {
            guard let y = calendar.date(byAdding: .day, value: -1, to: day), set.contains(y) else { return 0 }
            day = y
        }
        var count = 0
        while set.contains(day) {
            count += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return count
    }

    public static func longestStreak(days: [Date], calendar: Calendar = .current) -> Int {
        let sorted = Set(days.map { calendar.startOfDay(for: $0) }).sorted()
        var best = 0, run = 0
        var previous: Date?
        for d in sorted {
            if let p = previous, calendar.dateComponents([.day], from: p, to: d).day == 1 { run += 1 } else { run = 1 }
            best = max(best, run)
            previous = d
        }
        return best
    }
}
