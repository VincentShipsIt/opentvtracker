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

private struct SpaceModeContainer<PersonalContent: View, SharedContent: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: AppSpaceMode
    @State private var availableWidth: CGFloat = 0
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
        Group {
            switch selection {
            case .personal:
                personalContent
                    .transition(spaceTransition(edge: .leading))
            case .shared:
                sharedContent
                    .transition(spaceTransition(edge: .trailing))
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            SpaceModePicker(selection: $selection)
        }
        .contentShape(.rect)
        .simultaneousGesture(spaceSwipe)
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.width
        } action: { width in
            availableWidth = width
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: selection)
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityIdentifier("space-mode-container")
    }

    private var spaceSwipe: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onEnded { value in
                let horizontalDistance = value.translation.width
                let verticalDistance = value.translation.height

                guard abs(horizontalDistance) > 60,
                      abs(horizontalDistance) > abs(verticalDistance) * 1.25
                else {
                    return
                }

                if selection == .personal,
                   horizontalDistance < 0,
                   value.startLocation.x >= availableWidth - 44 {
                    selection = .shared
                } else if selection == .shared,
                          horizontalDistance > 0,
                          value.startLocation.x <= 44 {
                    selection = .personal
                }
            }
    }

    private func spaceTransition(edge: Edge) -> AnyTransition {
        reduceMotion ? .identity : .move(edge: edge).combined(with: .opacity)
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
