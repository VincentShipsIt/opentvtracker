import SwiftUI

@main
struct OpenTVTrackerApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(model)
                .task {
                    await model.load()
                }
        }
    }
}
