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

    /// The hue of this space. With no persistent label on screen, colour is what tells
    /// you which room you are in — the backdrop and every tinted control carry it, so a
    /// glance is enough.
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

    /// The live space selection, published so any screen can offer a way across.
    ///
    /// A segmented picker used to carry this, but it sat above every tab's content on
    /// every screen — permanent chrome for a control most sessions never touch. The
    /// sideways swipe is the switch now; this binding is what lets each root screen put
    /// a single toolbar button behind the same action.
    @Entry var appSpaceModeSelection: Binding<AppSpaceMode>?

    /// Open claims on horizontal drags, one token per region that currently owns them.
    ///
    /// The space swipe is a plain `DragGesture` attached above a whole tab, so it sees
    /// every sideways pan in the subtree — including the dozen horizontal shelves and
    /// anything pushed on top of a root screen. Rather than guess from coordinates, the
    /// regions that own a horizontal drag say so while they own it, and the swipe stands
    /// down whenever the set is non-empty.
    @Entry var spaceSwipeClaims: Binding<Set<UUID>>?
}

extension View {
    /// Marks a horizontally scrolling region. While it is actively scrolling, a sideways
    /// drag here belongs to the shelf, not to the space switch.
    func claimsHorizontalDrag() -> some View {
        modifier(HorizontalDragClaim())
    }

    /// Applied to a root screen's stack content. While something is pushed over that
    /// root, nothing sideways should swap the space out from under it — which is also
    /// what leaves `NavigationStack`'s own interactive back-swipe uncontested, without
    /// the space swipe having to reserve a screen edge for it.
    func suspendsSpaceSwipeWhenCovered() -> some View {
        modifier(SpaceSwipeSuspension())
    }
}

/// Claims the space swipe for the duration of a horizontal scroll.
struct HorizontalDragClaim: ViewModifier {
    @Environment(\.spaceSwipeClaims) private var claims
    @State private var token = UUID()

    func body(content: Content) -> some View {
        content
            .onScrollPhaseChange { _, phase in
                if phase == .idle {
                    claims?.wrappedValue.remove(token)
                } else {
                    claims?.wrappedValue.insert(token)
                }
            }
            .onDisappear { claims?.wrappedValue.remove(token) }
    }
}

/// Claims the space swipe for as long as the view it is applied to is covered.
///
/// Inverted on purpose: the claim is taken on `onDisappear` and released on `onAppear`.
/// A root screen disappears when anything is pushed over it, at any depth, so one
/// modifier on each root covers every detail screen in the app without touching them.
struct SpaceSwipeSuspension: ViewModifier {
    @Environment(\.spaceSwipeClaims) private var claims
    @Environment(\.appSpaceMode) private var space
    @Environment(\.appSpaceModeSelection) private var selection
    @State private var token = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { claims?.wrappedValue.remove(token) }
            .onDisappear {
                // Only a push over this root suspends the swipe. A root also disappears
                // because its space swapped out, and that is not a cover: the view is
                // gone, so the claim it took there is one nothing can ever hand back —
                // it would leave the destination space unable to swipe home again.
                // The binding reads live state, so by here it already names the space
                // being swiped to, while `space` still names the one being left.
                guard selection?.wrappedValue == space else { return }
                claims?.wrappedValue.insert(token)
            }
    }
}

/// The visible half of the space switch.
///
/// The swipe is the primary path, but a gesture with nothing on screen naming it is not
/// a feature anyone finds, and VoiceOver claims single-finger horizontal swipes for its
/// own element navigation — leaving the gesture alone would put the Shared space out of
/// reach under it entirely. Every root screen carries this button so both hold: the
/// swipe stays fast, and the switch stays discoverable and operable without it.
struct SpaceModeToggleButton: View {
    @Environment(\.appSpaceModeSelection) private var selection

    var body: some View {
        if let selection {
            let destination = selection.wrappedValue == .personal
                ? AppSpaceMode.shared
                : AppSpaceMode.personal

            Button {
                selection.wrappedValue = destination
            } label: {
                Label("Switch to \(destination.label)", systemImage: destination.symbol)
            }
            .accessibilityHint("You can also swipe left or right across the screen")
            .accessibilityIdentifier("space-mode-toggle")
        }
    }
}

extension View {
    /// Root screens only. Detail screens pushed onto a stack inherit their own back
    /// button and should not offer a second, sideways exit from the same bar.
    func spaceModeToolbar() -> some View {
        toolbar {
            ToolbarItem(placement: .topBarLeading) {
                SpaceModeToggleButton()
            }
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
        // Tab-bar chrome is app-level, not space-level: it stays put while the rooms
        // swap underneath it. `SpaceModeContainer` re-tints the content it wraps,
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

/// Personal and Shared swap in place. Swipe left for Shared, right for Personal; each
/// root screen's `spaceModeToolbar()` button is the same switch made visible.
///
/// A page-styled `TabView` was tried for this and rejected: wrapping each tab's
/// `NavigationStack` in a paged scroll container left pushed content resolving to an
/// empty frame, so controls inside a detail screen became unhittable. That is why the
/// switch is a `DragGesture` over a normal container rather than real horizontal paging.
private struct SpaceModeContainer<PersonalContent: View, SharedContent: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: AppSpaceMode
    @State private var availableWidth: CGFloat = 0
    @State private var claims: Set<UUID> = []
    @State private var isEligibleSwipe: Bool?
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
        .environment(\.appSpaceModeSelection, $selection)
        .environment(\.spaceSwipeClaims, $claims)
        // Both branches carry their own `AmbientBackdrop`, and the cross-fade dips both
        // below full opacity at once — without an opaque layer of our own underneath,
        // the window backdrop reads through as black gutters for the length of the
        // transition. One persistent backdrop here keeps every frame composited.
        .background {
            AmbientBackdrop()
                .environment(\.appSpaceMode, selection)
        }
        .contentShape(.rect)
        .simultaneousGesture(spaceSwipe)
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.width
        } action: { width in
            availableWidth = width
        }
        // Every claim belongs to a region in the space being retired, so the space
        // arriving starts clean. `SpaceSwipeSuspension` already declines to claim on a
        // swap; this is the backstop for a token whose owner lost its state while it
        // held one, which would otherwise wedge the swipe shut for good.
        .onChange(of: selection) { claims.removeAll() }
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: selection)
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityIdentifier("space-mode-container")
    }

    /// Swipe left for Shared, right for Personal — the same directions the two spaces
    /// animate in from, so the content follows the finger rather than flipping.
    ///
    /// Anywhere on the screen, no edge to find. The gesture is installed with
    /// `simultaneousGesture` above everything in the tab, so it would otherwise fire on
    /// shelf scrolls and fight `NavigationStack`'s interactive pop; `spaceSwipeClaims`
    /// is what settles those instead of a screen-edge anchor. Distance or momentum will
    /// do, which is what makes a quick flick land the same as a deliberate drag.
    ///
    /// `SpaceModeToggleButton` covers what a gesture cannot: naming itself on screen,
    /// and working under VoiceOver, which reserves horizontal swipes for its own use.
    private var spaceSwipe: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .local)
            .onChanged { _ in
                // Sampled once, the moment the pan becomes a drag. By `onEnded` a shelf
                // that took it may have coasted back to idle and dropped its claim.
                if isEligibleSwipe == nil {
                    isEligibleSwipe = claims.isEmpty
                }
            }
            .onEnded { value in
                let wasEligible = isEligibleSwipe ?? true
                isEligibleSwipe = nil
                guard wasEligible else { return }

                let travelled = value.translation.width
                guard abs(travelled) > abs(value.translation.height) * 1.5 else { return }

                let threshold = max(80, availableWidth * 0.2)
                let distance = abs(travelled) >= threshold
                    ? travelled
                    : value.predictedEndTranslation.width
                guard abs(distance) >= threshold else { return }

                selection = distance < 0 ? .shared : .personal
            }
    }

    private func spaceTransition(edge: Edge) -> AnyTransition {
        reduceMotion ? .identity : .move(edge: edge).combined(with: .opacity)
    }
}

#Preview {
    RootTabView(partnerSharingService: PreviewPartnerSharingService())
        .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
        .environment(\.allowsRemoteArtwork, false)
}
