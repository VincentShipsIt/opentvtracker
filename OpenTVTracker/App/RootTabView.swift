import SwiftUI

enum AppTab: Hashable {
    case today
    case discover
    case together
    case library
    case profile
}

struct RootTabView: View {
    @State private var selection: AppTab = .today

    var body: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "sparkles", value: .today) {
                TodayView()
                    .accessibilityIdentifier("tab.today")
            }

            Tab("Discover", systemImage: "safari", value: .discover) {
                DiscoverView()
                    .accessibilityIdentifier("tab.discover")
            }

            Tab("Together", systemImage: "person.2.fill", value: .together) {
                TogetherView()
                    .accessibilityIdentifier("tab.together")
            }

            Tab("Library", systemImage: "rectangle.stack.fill", value: .library) {
                LibraryView()
                    .accessibilityIdentifier("tab.library")
            }

            Tab("Profile", systemImage: "person.crop.circle.fill", value: .profile) {
                ProfileView()
                    .accessibilityIdentifier("tab.profile")
            }
        }
        .tint(.accentColor)
    }
}

#Preview {
    RootTabView()
        .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
        .environment(\.allowsRemoteArtwork, false)
}
