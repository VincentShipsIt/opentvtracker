import SwiftUI

enum AppTab: Hashable {
    case today
    case discover
    case library
}

enum AppSpaceMode: String, CaseIterable, Hashable, Identifiable {
    case personal
    case shared

    var id: Self { self }

    var label: String {
        switch self {
        case .personal: "Personal"
        case .shared: "Shared"
        }
    }

    var symbol: String {
        switch self {
        case .personal: "person.fill"
        case .shared: "person.2.fill"
        }
    }

    /// Primary ambient hue. The backdrop is the only "where am I" signal now that
    /// the segmented picker is gone, so the two modes must read as different rooms.
    var ambientTint: Color {
        switch self {
        case .personal: .accentColor
        case .shared: .pink
        }
    }

    /// Secondary wash layered under the primary tint.
    var ambientWash: Color {
        switch self {
        case .personal: .indigo
        case .shared: .purple
        }
    }

    var other: AppSpaceMode {
        self == .personal ? .shared : .personal
    }
}

extension EnvironmentValues {
    @Entry var appSpaceMode: AppSpaceMode = .personal
}

struct RootTabView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: AppTab = .today
    @State private var spaceMode: AppSpaceMode = .personal
    @State private var discoverSearchText = ""
    @State private var presentsFirstRun = false
    let partnerSharingService: any PartnerSharingProviding

    var body: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "sun.max.fill", value: .today) {
                SpaceModeContainer(selection: $spaceMode) {
                    TodayView(selectedTab: $selection)
                } shared: {
                    TogetherView(
                        page: .today,
                        sharingService: partnerSharingService
                    )
                }
                    .accessibilityIdentifier("tab.today")
            }

            Tab(
                "Discover",
                systemImage: "magnifyingglass",
                value: .discover,
                role: .search
            ) {
                SpaceModeContainer(selection: $spaceMode) {
                    DiscoverView(
                        spaceMode: .personal,
                        searchText: $discoverSearchText
                    )
                } shared: {
                    DiscoverView(
                        spaceMode: .shared,
                        searchText: $discoverSearchText
                    )
                }
                    .task(id: discoverSearchText) {
                        await model.searchCatalog(text: discoverSearchText)
                    }
                    .accessibilityIdentifier("tab.discover")
            }

            Tab("Library", systemImage: "rectangle.stack.fill", value: .library) {
                SpaceModeContainer(selection: $spaceMode) {
                    LibraryView(selectedTab: $selection)
                } shared: {
                    TogetherView(
                        page: .library,
                        sharingService: partnerSharingService
                    )
                }
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

/// Personal and Shared are two pages of one horizontally paged surface — there is no
/// picker chrome. A page `TabView` gives a finger-tracking swipe that also cooperates
/// with the horizontal shelves inside each page (an inner shelf consumes the pan until
/// it reaches its content edge), which a raw `DragGesture` could not do.
private struct SpaceModeContainer<PersonalContent: View, SharedContent: View>: View {
    @Binding var selection: AppSpaceMode
    private let personalContent: PersonalContent
    private let sharedContent: SharedContent

    init(
        selection: Binding<AppSpaceMode>,
        @ViewBuilder personal: () -> PersonalContent,
        @ViewBuilder shared: () -> SharedContent
    ) {
        _selection = selection
        personalContent = personal()
        sharedContent = shared()
    }

    var body: some View {
        TabView(selection: $selection) {
            personalContent
                .environment(\.appSpaceMode, .personal)
                .tag(AppSpaceMode.personal)

            sharedContent
                .environment(\.appSpaceMode, .shared)
                .tag(AppSpaceMode.shared)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .sensoryFeedback(.selection, trigger: selection)
        // The swipe is the only way to change space, so VoiceOver (which cannot
        // deliver the page pan) gets an explicit rotor action instead.
        .accessibilityAction(named: Text("Switch to \(selection.other.label) space")) {
            selection = selection.other
        }
        .accessibilityIdentifier("space-mode-container")
    }
}

#Preview {
    RootTabView(partnerSharingService: PreviewPartnerSharingService())
        .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
        .environment(\.allowsRemoteArtwork, false)
}
