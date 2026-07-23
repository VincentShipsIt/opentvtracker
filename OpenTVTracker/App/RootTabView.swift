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
}

struct RootTabView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: AppTab = .today
    @State private var spaceMode: AppSpaceMode = .personal
    @State private var presentsFirstRun = false
    let partnerSharingService: any PartnerSharingProviding

    var body: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "sun.max.fill", value: .today) {
                SpaceModePager(selection: $spaceMode) {
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
                SpaceModePager(selection: $spaceMode) {
                    DiscoverView(spaceMode: .personal)
                } shared: {
                    DiscoverView(spaceMode: .shared)
                }
                    .accessibilityIdentifier("tab.discover")
            }

            Tab("Library", systemImage: "rectangle.stack.fill", value: .library) {
                SpaceModePager(selection: $spaceMode) {
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

private struct SpaceModePager<PersonalContent: View, SharedContent: View>: View {
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
                .tag(AppSpaceMode.personal)

            sharedContent
                .tag(AppSpaceMode.shared)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .safeAreaInset(edge: .top, spacing: 0) {
            SpaceModePicker(selection: $selection)
        }
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityIdentifier("space-mode-pager")
    }
}

private struct SpaceModePicker: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var selection: AppSpaceMode

    var body: some View {
        GlassSurface(cornerRadius: AppTheme.compactRadius) {
            if dynamicTypeSize.isAccessibilitySize {
                Picker("Viewing space", selection: $selection) {
                    modes
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
            } else {
                Picker("Viewing space", selection: $selection) {
                    modes
                }
                .pickerStyle(.segmented)
                .padding(6)
            }
        }
        .padding(.horizontal, AppTheme.horizontalPadding)
        .padding(.vertical, 8)
        .accessibilityHint("Swipe left or right on the content to change space")
        .accessibilityIdentifier("space-mode-picker")
    }

    @ViewBuilder
    private var modes: some View {
        ForEach(AppSpaceMode.allCases) { mode in
            Label(mode.label, systemImage: mode.symbol)
                .tag(mode)
        }
    }
}

#Preview {
    RootTabView(partnerSharingService: PreviewPartnerSharingService())
        .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
        .environment(\.allowsRemoteArtwork, false)
}
