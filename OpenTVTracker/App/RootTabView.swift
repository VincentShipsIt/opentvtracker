import SwiftUI

enum AppTab: Hashable {
    case today
    case discover
    case together
    case library
}

struct RootTabView: View {
    @State private var selection: AppTab = .today

    var body: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "sparkles", value: .today) {
                TodayView()
            }

            Tab("Discover", systemImage: "safari", value: .discover) {
                DiscoverView()
            }

            Tab("Together", systemImage: "person.2.fill", value: .together) {
                TogetherView()
            }

            Tab("Library", systemImage: "rectangle.stack.fill", value: .library) {
                LibraryView()
            }
        }
        .tint(.accentColor)
    }
}

#Preview {
    RootTabView()
        .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
}
