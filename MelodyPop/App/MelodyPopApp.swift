import SwiftData
import SwiftUI

@main
struct MelodyPopApp: App {
    @State private var app: AppModel
    private let container: ModelContainer

    init() {
        let model = AppModel()
        _app = State(initialValue: model)
        container = DataStore.makeContainer(inMemory: AppModel.isUITesting)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(app.play)
                .preferredColorScheme(.light)
                .tint(Theme.lavenderDeep)
        }
        .modelContainer(container)
    }
}
