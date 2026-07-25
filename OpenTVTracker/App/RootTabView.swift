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

    /// The hue of this space. The picker names the current space; the backdrop and
    /// every tinted control reinforce it so the two modes also *read* as different
    /// rooms.
    ///
    /// `SpaceModeContainer` installs this as the SwiftUI tint for the space it wraps,
    /// so controls inside must resolve their accent from `.tint` rather than reaching
    /// for `Color.accentColor` — that resolves to the asset-catalog accent and stays
    /// blue in a magenta room.
    var accent: Color {
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
        // Tab-bar chrome is app-level, not space-level: it stays put while the picker
        // swaps rooms underneath it. `SpaceModeContainer` re-tints the content it wraps,
        // which sits deeper and therefore wins inside each tab.
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

/// Personal and Shared swap in place behind an explicit picker.
///
/// A page-styled `TabView` was tried here and rejected: wrapping each tab's
/// `NavigationStack` in a paged scroll container left pushed content resolving to an
/// empty frame, so controls inside a detail screen became unhittable. It also left the
/// Shared space reachable only by an undiscoverable swipe. The picker stays.
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
                    .environment(\.appSpaceMode, .personal)
                    .tint(AppSpaceMode.personal.accent)
                    .transition(spaceTransition(edge: .leading))
            case .shared:
                sharedContent
                    .environment(\.appSpaceMode, .shared)
                    .tint(AppSpaceMode.shared.accent)
                    .transition(spaceTransition(edge: .trailing))
            }
        }
        // Both branches carry their own `AmbientBackdrop`, and the cross-fade dips both
        // below full opacity at once — without an opaque layer of our own underneath,
        // the window backdrop reads through as black gutters for the length of the
        // transition. One persistent backdrop here keeps every frame composited.
        .background {
            AmbientBackdrop()
                .environment(\.appSpaceMode, selection)
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

    /// Edge-started only: a drag beginning mid-screen belongs to whatever horizontal
    /// shelf is under the finger, not to the space switch.
    ///
    /// This is a *toggle*, not a pair of directional swipes: pull in from the trailing
    /// edge to flip to the other space, whichever one you are in. The leading edge is
    /// reserved for `NavigationStack`'s interactive pop, and this gesture is installed
    /// with `simultaneousGesture` above a stack that every space pushes onto — a
    /// leading-edge start would fire both recognizers, popping the detail screen *and*
    /// throwing the user into the other space in one swipe. That rules out a rightward
    /// return swipe entirely: anchored trailing it has no room to travel (the finger
    /// would have to leave the screen to clear the distance threshold), and anchored
    /// leading it collides with the pop. Symmetry is the only reachable shape left.
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
                          horizontalDistance < 0,
                          value.startLocation.x >= availableWidth - 44 {
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
        // No gesture hint here: VoiceOver claims single-finger horizontal swipes for its
        // own element navigation, so the edge swipe is unreachable under it. The picker
        // itself is the accessible path and needs no explaining.
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
