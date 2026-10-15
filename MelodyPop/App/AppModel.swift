import Foundation
import MelodyPopKit
import Observation
import SwiftData

@Observable
@MainActor
final class AppModel {
    static let isUITesting = ProcessInfo.processInfo.arguments.contains("-uitest")

    let play: PlayModeController
    let store: StoreManager
    var currentStudentID: UUID? {
        didSet { UserDefaults.standard.set(currentStudentID?.uuidString, forKey: "currentStudentID") }
    }
    /// Shows Play Mode Selection the first time a new student starts.
    var needsModeSelection: Bool {
        didSet { UserDefaults.standard.set(!needsModeSelection, forKey: "didChooseMode") }
    }

    init() {
        if AppModel.isUITesting, let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
            if ProcessInfo.processInfo.arguments.contains("-uitest-skip-mode-selection") {
                UserDefaults.standard.set(true, forKey: "didChooseMode")
            }
        }
        play = PlayModeController(initialMode: AppModel.isUITesting ? .touch : nil)
        store = StoreManager()
        currentStudentID = UserDefaults.standard.string(forKey: "currentStudentID").flatMap(UUID.init(uuidString:))
        needsModeSelection = !UserDefaults.standard.bool(forKey: "didChooseMode")
    }

    func currentStudent(in context: ModelContext) -> StudentProfile? {
        let all = (try? context.fetch(FetchDescriptor<StudentProfile>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        if let id = currentStudentID, let match = all.first(where: { $0.id == id }) { return match }
        return all.first
    }

    /// UI tests can pass `-uitest-student Name` to start with a profile.
    func seedForUITests(context: ModelContext) {
        let args = ProcessInfo.processInfo.arguments
        guard AppModel.isUITesting, let i = args.firstIndex(of: "-uitest-student"), i + 1 < args.count else { return }
        let existing = (try? context.fetch(FetchDescriptor<StudentProfile>())) ?? []
        guard existing.isEmpty else { return }
        let s = StudentProfile(name: args[i + 1])
        context.insert(s)
        try? context.save()
        currentStudentID = s.id
    }
}
