import SwiftUI
import UIKit

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
    /// every screen — permanent chrome for a control most sessions never touch. A shake
    /// is the switch now; this binding is what lets each root screen put a single
    /// toolbar button behind the same action.
    @Entry var appSpaceModeSelection: Binding<AppSpaceMode>?

    /// Whatever is currently holding the space switch back, if anything is.
    @Entry var spaceSwitchSuspension: SpaceSwitchSuspension?
}

extension Notification.Name {
    /// Posted once per physical shake, by the window that received it.
    static let openTVSpaceShakeDetected = Notification.Name("OpenTVSpaceShakeDetected")
}

/// The one vantage point from which a shake is always visible.
///
/// UIKit delivers motion events to the first responder and then up the responder chain, so
/// a detector parked on a view of our own only sees a shake while nothing else holds the
/// keyboard — Discover's search field alone would blind it. The window is the last stop on
/// every chain, so nothing can take the event away from it first. SwiftUI never hands the
/// window over, hence the extension.
extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        guard motion == .motionShake else { return }
        // A sheet or cover leaves the space's root mounted underneath it, so
        // `CoveredSpaceSuspension` — which keys off the root disappearing — never fires for
        // one. Asking the window instead covers every presentation in the app at once,
        // including first run, which is presented above all three containers and so is
        // reached by no suspension of theirs. It also means the next sheet somebody adds
        // cannot forget to opt in.
        guard !hasPresentedViewController else { return }
        NotificationCenter.default.post(name: .openTVSpaceShakeDetected, object: nil)
    }

    /// Whether anything anywhere beneath this window is presenting modally.
    ///
    /// SwiftUI picks the presenting controller itself, and for a `.sheet` deep inside a
    /// navigation stack that is not the root — so the whole subtree has to be walked rather
    /// than only `rootViewController.presentedViewController`. Runs once per shake.
    private var hasPresentedViewController: Bool {
        var pending = [rootViewController].compactMap { $0 }
        while let controller = pending.popLast() {
            if controller.presentedViewController != nil { return true }
            pending.append(contentsOf: controller.children)
        }
        return false
    }
}

/// Whatever is holding the space switch back, kept deliberately outside SwiftUI's
/// observation.
///
/// It is written when a screen is covered or uncovered and read once per shake, and its
/// only reader is the container that owns it. Publishing it through `@State` would
/// invalidate the body of an entire tab to tell that tab something it consults on demand.
/// A plain reference box has no observers to notify.
@MainActor
final class SpaceSwitchSuspension {
    private var holders: Set<UUID> = []

    var isSuspended: Bool { !holders.isEmpty }

    func suspend(_ token: UUID) {
        holders.insert(token)
    }

    func resume(_ token: UUID) {
        holders.remove(token)
    }
}

extension View {
    /// Applied to a root screen's stack content. While something is pushed over that root,
    /// a shake must not swap the space out from under it: the pushed screen was opened
    /// from this space and the other one has nothing equivalent to land on.
    func suspendsSpaceSwitchWhenCovered() -> some View {
        modifier(CoveredSpaceSuspension())
    }
}

/// Suspends the space switch for as long as the view it is applied to is covered.
///
/// Inverted on purpose: it holds on `onDisappear` and releases on `onAppear`. A root screen
/// disappears when anything is pushed over it, at any depth, so one modifier on each root
/// covers every detail screen in the app without touching them.
struct CoveredSpaceSuspension: ViewModifier {
    @Environment(\.spaceSwitchSuspension) private var suspension
    @Environment(\.appSpaceMode) private var space
    @Environment(\.appSpaceModeSelection) private var selection
    @State private var token = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { suspension?.resume(token) }
            .onDisappear {
                // Only a push over this root suspends the switch. A root also disappears
                // because its space swapped out, and that is not a cover: the view is
                // gone, so a hold placed there is one nothing can ever release — it would
                // leave the destination space unable to shake its way home again. The
                // binding reads live state, so by here it already names the space being
                // switched to, while `space` still names the one being left.
                guard selection?.wrappedValue == space else { return }
                suspension?.suspend(token)
            }
    }
}

/// The visible half of the space switch.
///
/// A shake is fast and impossible to trigger by accident while reading, but it names
/// nothing on screen, it is out of reach for anyone who cannot shake the phone, and
/// VoiceOver offers no way to perform it at all. Every root screen carries this button so
/// both hold: the shake stays fun, and the switch stays discoverable and operable without
/// it.
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
            .accessibilityHint("You can also shake your phone to switch spaces")
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
                SpaceModeContainer(selection: $spaceMode, isActive: selection == .today) {
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
                SpaceModeContainer(selection: $spaceMode, isActive: selection == .discover) {
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
                SpaceModeContainer(selection: $spaceMode, isActive: selection == .library) {
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

/// Personal and Shared swap in place. Shake the phone to cross over; each root screen's
/// `spaceModeToolbar()` button is the same switch made visible.
///
/// Two other switches were tried here first. A page-styled `TabView` was rejected because
/// wrapping each tab's `NavigationStack` in a paged scroll container left pushed content
/// resolving to an empty frame, so controls inside a detail screen became unhittable. A
/// sideways `DragGesture` replaced it and was rejected in turn: installed above a whole
/// tab it saw every horizontal pan in the subtree, so each shelf had to publish its frame
/// and the gesture had to hit-test against all of them — a dozen rects updating at scroll
/// rate to arbitrate a gesture that also had to stay out of the way of the interactive
/// back-swipe. A shake shares no vocabulary with anything on screen, so none of that
/// arbitration exists to get wrong.
private struct SpaceModeContainer<PersonalContent: View, SharedContent: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: AppSpaceMode

    /// Whether this container is the one on screen.
    ///
    /// One of these is mounted per tab and every visited tab stays mounted, so a single
    /// shake reaches all three. Without this gate all three would flip the same binding in
    /// sequence and the odd one out would win.
    let isActive: Bool

    @State private var suspension = SpaceSwitchSuspension()

    private let personalContent: PersonalContent
    private let sharedContent: SharedContent

    init(
        selection: Binding<AppSpaceMode>,
        isActive: Bool,
        @ViewBuilder personal: () -> PersonalContent,
        @ViewBuilder shared: () -> SharedContent
    ) {
        _selection = selection
        self.isActive = isActive
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
        .environment(\.spaceSwitchSuspension, suspension)
        // Both branches carry their own `AmbientBackdrop`, and the cross-fade dips both
        // below full opacity at once — without an opaque layer of our own underneath,
        // the window backdrop reads through as black gutters for the length of the
        // transition. One persistent backdrop here keeps every frame composited.
        .background {
            AmbientBackdrop()
                .environment(\.appSpaceMode, selection)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openTVSpaceShakeDetected)) { _ in
            switchSpaces()
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: selection)
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityIdentifier("space-mode-container")
    }

    private func switchSpaces() {
        guard isActive, !suspension.isSuspended else { return }
        selection = selection == .personal ? .shared : .personal
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
