import SwiftUI

enum AppTab: Hashable {
    case today
    case discover
    case together
    case library
}

struct RootTabView: View {
    @State private var selection: AppTab = .today
    let partnerSharingService: any PartnerSharingProviding

    var body: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "sun.max.fill", value: .today) {
                TodayView()
                    .accessibilityIdentifier("tab.today")
            }

            Tab(
                "Discover",
                systemImage: "magnifyingglass",
                value: .discover,
                role: .search
            ) {
                DiscoverView()
                    .accessibilityIdentifier("tab.discover")
            }

            Tab("Together", systemImage: "person.2.fill", value: .together) {
                TogetherView(sharingService: partnerSharingService)
                    .accessibilityIdentifier("tab.together")
            }

            Tab("Library", systemImage: "rectangle.stack.fill", value: .library) {
                LibraryView()
                    .accessibilityIdentifier("tab.library")
            }
        }
        .tint(.accentColor)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    RootTabView(partnerSharingService: PreviewPartnerSharingService())
        .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
        .environment(\.allowsRemoteArtwork, false)
}
