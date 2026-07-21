import SwiftUI

enum AppTab: Hashable {
    case today
    case discover
    case together
    case library
}

struct RootTabView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: AppTab = .today
    @State private var presentsFirstRun = false
    let partnerSharingService: any PartnerSharingProviding

    var body: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "sun.max.fill", value: .today) {
                TodayView(selectedTab: $selection)
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
        .fullScreenCover(isPresented: $presentsFirstRun) {
            FirstRunView(partnerSharingService: partnerSharingService)
        }
        .task(id: model.hasLoaded) {
            guard model.hasLoaded, !model.hasCompletedFirstRun else { return }
            presentsFirstRun = true
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    RootTabView(partnerSharingService: PreviewPartnerSharingService())
        .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
        .environment(\.allowsRemoteArtwork, false)
}
