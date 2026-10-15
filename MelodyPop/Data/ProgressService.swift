import Foundation
import MelodyPopKit
import SwiftData

typealias Sticker = StickerDefinition

@MainActor
enum ProgressService {
    /// Saves a finished lesson/song run and returns any stickers it newly unlocked.
    @discardableResult
    static func record(item: PracticeItem, result: SessionResult, seconds: TimeInterval, source: InputSource, student: StudentProfile, context: ModelContext) -> [Sticker] {
        if item.kind == .lesson {
            let progress: LessonProgress
            if let existing = student.progress(for: item.id) {
                progress = existing
            } else {
                progress = LessonProgress(lessonID: item.id)
                context.insert(progress)
                progress.student = student
            }
            progress.attempts += 1
            progress.lastPlayed = .now
            progress.bestAccuracy = max(progress.bestAccuracy, result.accuracy)
            progress.bestStars = max(progress.bestStars, result.stars)
            if result.accuracy >= item.passAccuracy { progress.completed = true }
        }
        let activity = item.kind == .lesson ? "lesson" : (result.accuracy >= item.passAccuracy ? "song" : "songAttempt")
        log(activity: activity, itemID: item.id, title: item.title, seconds: seconds, accuracy: result.accuracy, source: source, student: student, context: context)
        return awardStickers(student: student, context: context, perfectRun: result.accuracy >= 0.999)
    }

    static func log(activity: String, itemID: Int, title: String, seconds: TimeInterval, accuracy: Double, score: Int = 0, source: InputSource, student: StudentProfile, context: ModelContext) {
        let entry = PracticeLog(seconds: max(0, seconds), activity: activity, itemID: itemID, itemTitle: title, accuracy: accuracy, score: score, inputSource: source)
        context.insert(entry)
        entry.student = student
        try? context.save()
    }

    static func snapshot(for student: StudentProfile) -> ProgressSnapshot {
        var s = ProgressSnapshot()
        s.completedLessons = student.completedLessonIDs
        s.threeStarLessons = student.lessonProgress.filter { $0.bestStars == 3 }.count
        s.totalStars = student.totalStars
        s.practiceDays = student.practiceLogs.map(\.date)
        s.songsCompleted = Set(student.practiceLogs.filter { $0.activity == "song" }.map(\.itemID)).count
        s.gamesPlayed = student.practiceLogs.filter { $0.activity == "game" }.count
        s.perfectRuns = student.practiceLogs.filter { $0.accuracy >= 0.999 && ($0.activity == "lesson" || $0.activity == "song") }.count
        s.recordings = student.recordings.count
        s.minutesPracticed = student.practiceLogs.reduce(0) { $0 + $1.seconds } / 60
        s.sourcesUsed = Set(student.practiceLogs.compactMap { InputSource(rawValue: $0.inputSource) })
        s.bestGameScore = student.practiceLogs.filter { $0.activity == "game" }.map(\.score).max() ?? 0
        return s
    }

    @discardableResult
    static func awardStickers(student: StudentProfile, context: ModelContext, perfectRun: Bool = false) -> [Sticker] {
        var snap = snapshot(for: student)
        if perfectRun { snap.perfectRuns = max(1, snap.perfectRuns) }
        let earnedIDs = RewardRules.earned(snap)
        let have = Set(student.stickers.map(\.stickerID))
        let new = RewardRules.all.filter { earnedIDs.contains($0.id) && !have.contains($0.id) }
        for sticker in new {
            let e = EarnedSticker(stickerID: sticker.id)
            context.insert(e)
            e.student = student
        }
        try? context.save()
        return new
    }
}
