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

    /// The regions a sideways drag must not start in for it to be a space switch.
    ///
    /// The space swipe is a plain `DragGesture` attached above a whole tab, so it sees
    /// every sideways pan in the subtree — including the dozen horizontal shelves and
    /// anything pushed on top of a root screen. Those regions publish where they are, and
    /// the gesture hit-tests the touch-down point against them once.
    @Entry var spaceSwipeExclusions: SpaceSwipeExclusions?
}

/// The coordinate space shelf frames and drag locations are both expressed in.
///
/// `.local` would mean each shelf measuring against itself, which says nothing about
/// where the finger landed. One named space installed on the container makes the two
/// comparable: `frame(in:)` on the way in, `startLocation` on the way out.
enum SpaceSwipeGeometry {
    static let spaceName = "space-mode-container"
    static var space: NamedCoordinateSpace { .named(spaceName) }
}

/// Where the space swipe must not start, kept deliberately outside SwiftUI's observation.
///
/// Every entry is refreshed whenever its region moves, which for a shelf inside a
/// vertically scrolling screen means every frame of every scroll — a dozen shelves at
/// display rate. Publishing that through `@State` or `@Observable` would invalidate the
/// body of an entire tab on each tick, to inform one gesture that reads the whole set
/// exactly once per drag. A plain reference box has no observers to notify, so writing to
/// it costs nothing and renders nothing.
@MainActor
final class SpaceSwipeExclusions {
    private var regions: [UUID: CGRect] = [:]

    func setRegion(_ rect: CGRect, for token: UUID) {
        regions[token] = rect
    }

    func removeRegion(for token: UUID) {
        regions[token] = nil
    }

    func contains(_ point: CGPoint) -> Bool {
        regions.values.contains { $0.contains(point) }
    }
}

extension View {
    /// Marks a horizontally scrolling region. A sideways drag that starts inside its
    /// bounds belongs to the shelf, not to the space switch.
    ///
    /// Prefer `HorizontalShelf`, which applies this for you; reach for the modifier
    /// directly only where a scroll view cannot be routed through that component.
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

/// Publishes a horizontal region's frame so a drag starting inside it is left alone.
///
/// This used to claim the gesture on `onScrollPhaseChange` instead, and that race was
/// unwinnable: a scroll view only reports a phase once it has recognized its own pan
/// (around 10pt), while the space gesture wakes at 20pt of travel, and nothing orders the
/// two. A flick across a shelf was a coin flip. A frame is known before the finger lands,
/// so the same question has a deterministic answer.
struct HorizontalDragClaim: ViewModifier {
    @Environment(\.spaceSwipeExclusions) private var exclusions
    @State private var token = UUID()

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { geometry in
                geometry.frame(in: SpaceSwipeGeometry.space)
            } action: { frame in
                exclusions?.setRegion(frame, for: token)
            }
            .onDisappear { exclusions?.removeRegion(for: token) }
    }
}

/// Suspends the space swipe for as long as the view it is applied to is covered.
///
/// Inverted on purpose: the region is published on `onDisappear` and withdrawn on
/// `onAppear`. A root screen disappears when anything is pushed over it, at any depth, so
/// one modifier on each root covers every detail screen in the app without touching them.
struct SpaceSwipeSuspension: ViewModifier {
    @Environment(\.spaceSwipeExclusions) private var exclusions
    @Environment(\.appSpaceMode) private var space
    @Environment(\.appSpaceModeSelection) private var selection
    @State private var token = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { exclusions?.removeRegion(for: token) }
            .onDisappear {
                // Only a push over this root suspends the swipe. A root also disappears
                // because its space swapped out, and that is not a cover: the view is
                // gone, so a region published there is one nothing can ever withdraw —
                // it would leave the destination space unable to swipe home again.
                // The binding reads live state, so by here it already names the space
                // being swiped to, while `space` still names the one being left.
                guard selection?.wrappedValue == space else { return }
                // A cover is not a rectangle on screen, it is everything: no sideways
                // drag anywhere belongs to the switch while a detail screen is up. An
                // infinite rect contains any finite point, which lets one hit test answer
                // both questions instead of the gesture carrying a second mechanism.
                exclusions?.setRegion(.infinite, for: token)
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
    @State private var exclusions = SpaceSwipeExclusions()

    /// How far the current drag has carried the room sideways.
    ///
    /// `@GestureState` rather than `@State` because SwiftUI resets it on cancellation as
    /// well as on a clean end. A gesture interrupted by a phone call never reaches
    /// `onEnded`, and plain state would leave the screen shoved permanently off-centre
    /// with no way back. The reset animates, which is what snaps the room home when a
    /// drag stops short of the threshold.
    @GestureState(resetTransaction: Transaction(animation: .snappy(duration: 0.25)))
    private var drag: CGFloat = 0

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
        .environment(\.spaceSwipeExclusions, exclusions)
        // Applied before the backdrop below, so only the room moves. A `.background` added
        // after an `.offset` is not carried by it, which leaves an opaque layer filling
        // the gutter the room uncovers — no `.clipped()` needed, and none wanted: clipping
        // here would cut the navigation bar's own shadow and swallow hit testing at the
        // edges.
        .offset(x: contentOffset)
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
        // Outermost, so the gesture above and every `claimsHorizontalDrag()` below resolve
        // the same origin.
        .coordinateSpace(SpaceSwipeGeometry.space)
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.width
        } action: { width in
            availableWidth = width
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: selection)
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityIdentifier("space-mode-container")
    }

    /// How far to carry the room, given where the finger is and whether there is anywhere
    /// to go in that direction.
    ///
    /// Dragging towards the space you are already in has no destination, so it resists at a
    /// fifth of the distance instead of pulling a void into view — the same language as a
    /// scroll view at the end of its content, and enough feedback to say "not this way".
    private var contentOffset: CGFloat {
        guard drag != 0 else { return 0 }
        let hasDestination = drag < 0 ? selection == .personal : selection == .shared
        return hasDestination ? drag : drag * 0.2
    }

    /// Swipe left for Shared, right for Personal — the same directions the two spaces
    /// animate in from, so the content follows the finger rather than flipping.
    ///
    /// Anywhere on the screen, no edge to find. The gesture is installed with
    /// `simultaneousGesture` above everything in the tab, so it would otherwise fire on
    /// shelf scrolls and fight `NavigationStack`'s interactive pop; `spaceSwipeExclusions`
    /// is what settles those instead of a screen-edge anchor. Distance or momentum will
    /// do, which is what makes a quick flick land the same as a deliberate drag.
    ///
    /// `SpaceModeToggleButton` covers what a gesture cannot: naming itself on screen,
    /// and working under VoiceOver, which reserves horizontal swipes for its own use.
    private var spaceSwipe: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: SpaceSwipeGeometry.space)
            .updating($drag) { value, drag, transaction in
                guard !reduceMotion, ownsDrag(value) else { return }
                // Nothing to interpolate while a finger is down: the room is wherever the
                // touch is. The reset transaction supplies the animation on release.
                transaction.animation = nil
                drag = value.translation.width
            }
            .onEnded { value in
                guard ownsDrag(value) else { return }

                let threshold = max(80, availableWidth * 0.2)
                let travelled = value.translation.width
                let distance = abs(travelled) >= threshold
                    ? travelled
                    : value.predictedEndTranslation.width
                guard abs(distance) >= threshold else { return }

                selection = distance < 0 ? .shared : .personal
            }
    }

    /// Whether this drag is the space switch's to act on.
    ///
    /// Recomputed from the gesture value in both callbacks rather than latched in state:
    /// hit testing the touch-down point is deterministic, so asking twice cannot disagree
    /// — which is exactly what the scroll-phase claims this replaced could not promise.
    /// It also keeps `onEnded` off `@GestureState`, whose reset is not ordered against it.
    private func ownsDrag(_ value: DragGesture.Value) -> Bool {
        guard exclusions.contains(value.startLocation) == false else { return false }
        return abs(value.translation.width) > abs(value.translation.height) * 1.5
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
