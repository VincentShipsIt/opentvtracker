import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @Binding var selectedTab: AppTab
    @State private var section: LibrarySection = .titles
    @State private var shelf: LibraryShelf = .keepWatching
    @State private var presentedSheet: LibrarySheet?

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackdrop()

                VStack(spacing: AppTheme.controlSpacing) {
                    switch section {
                    case .titles:
                        LibraryShelfPicker(selection: $shelf, titles: model.titles)
                        LibraryTitlesView(
                            titles: model.titles.filter(shelf.includes),
                            shelf: shelf,
                            onOpenDiscover: openDiscover,
                            onSelectShelf: { shelf = $0 }
                        )
                    case .lists:
                        CustomListsView()
                    case .history:
                        LibraryHistoryView(
                            onOpenDiscover: openDiscover,
                            onOpenDataTools: { presentedSheet = .dataTools }
                        )
                    }
                }
            }
            .suspendsSpaceSwitchWhenCovered()
            // Same shape as Today and Discover: system large title, one row of icons in
            // the trailing toolbar group, nothing duplicated in the scroll content. The
            // old screen stacked a hand-rolled title bar, a segmented control, and the
            // shelf pills into four tiers of chrome before a single title appeared.
            .navigationTitle(section.navigationTitle)
            .navigationBarTitleDisplayMode(.large)
            .accessibilityIdentifier("library.root")
            .onChange(of: section) { _, newSection in
                AccessibilityNotification.Announcement(newSection.navigationTitle).post()
            }
            .spaceModeToolbar()
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    LibrarySectionMenu(selection: $section)

                    Button("Profile and settings", systemImage: "person.crop.circle") {
                        presentedSheet = .settings
                    }
                    .accessibilityHint("Opens your private profile, app settings, and backup status")
                    .accessibilityIdentifier("library.settings")
                }
            }
            .sheet(item: $presentedSheet) { sheet in
                switch sheet {
                case .dataTools:
                    LibraryDataView()
                case .settings:
                    AppSettingsView()
                }
            }
            .navigationDestination(for: MediaTitle.self) { title in
                MediaDetailView(titleID: title.id)
            }
        }
    }

    private func openDiscover() {
        selectedTab = .discover
    }
}

private enum LibrarySheet: String, Identifiable {
    case dataTools
    case settings

    var id: Self { self }
}

enum LibrarySection: String, CaseIterable, Identifiable {
    case titles
    case lists
    case history

    var id: Self { self }

    var label: String {
        switch self {
        case .titles: "Titles"
        case .lists: "Lists"
        case .history: "History"
        }
    }

    var navigationTitle: String {
        switch self {
        case .titles: "Library"
        case .lists: "Lists"
        case .history: "History"
        }
    }

    var symbol: String {
        switch self {
        case .titles: "rectangle.stack"
        case .lists: "list.bullet.rectangle"
        case .history: "clock.arrow.trianglehead.counterclockwise.rotate.90"
        }
    }
}

enum LibraryShelf: String, CaseIterable, Identifiable {
    case keepWatching
    case watchlist
    case paused
    case completed
    case caughtUp
    case dropped

    var id: Self { self }

    var label: String {
        switch self {
        case .keepWatching: "Keep Watching"
        case .watchlist: "Watchlist"
        case .paused: "Paused"
        case .completed: "Completed"
        case .caughtUp: "Caught Up"
        case .dropped: "Dropped"
        }
    }

    var symbol: String {
        switch self {
        case .keepWatching: "play.circle.fill"
        case .watchlist: "bookmark.fill"
        case .paused: "pause.circle.fill"
        case .completed: "checkmark.circle.fill"
        case .caughtUp: "checkmark.seal.fill"
        case .dropped: "xmark.circle.fill"
        }
    }

    func includes(_ title: MediaTitle) -> Bool {
        switch self {
        case .keepWatching:
            title.state == .watching
        case .watchlist:
            title.isOnPersonalWatchlist
        case .paused:
            title.state == .paused
        case .completed:
            title.state == .completed
        case .caughtUp:
            title.state == .caughtUp
        case .dropped:
            title.state == .dropped
        }
    }

    var emptyTitle: String {
        switch self {
        case .keepWatching: "Nothing in progress"
        case .watchlist: "Your watchlist is empty"
        case .paused: "Nothing is paused"
        case .completed: "Nothing completed yet"
        case .caughtUp: "No continuing series are caught up"
        case .dropped: "Nothing dropped"
        }
    }

    var emptyDescription: String {
        switch self {
        case .keepWatching: "Start a title from Discover and it will appear here."
        case .watchlist: "Save something from Discover for later."
        case .paused: "Pause a title when you want to keep your place without seeing it in Keep Watching."
        case .completed: "Mark a movie or finished series watched to build your private history."
        case .caughtUp: "Continuing series with every released episode watched will appear here."
        case .dropped: "Titles you stop watching remain available here without losing their progress."
        }
    }

    var emptyActionTitle: String {
        switch self {
        case .paused, .caughtUp, .dropped: "Show Keep Watching"
        case .keepWatching, .watchlist, .completed: "Browse Discover"
        }
    }

    var emptyActionShelf: LibraryShelf? {
        switch self {
        case .paused, .caughtUp, .dropped: .keepWatching
        case .keepWatching, .watchlist, .completed: nil
        }
    }
}

/// Titles / Lists / History, folded into one toolbar glyph.
///
/// A segmented control costs a full-width row of permanent chrome to switch between
/// three views the user is mostly not switching between. An inline `Picker` inside a
/// `Menu` keeps the native checkmark and the current selection in the glyph itself,
/// and costs one icon in the row that already holds the profile button.
private struct LibrarySectionMenu: View {
    @Binding var selection: LibrarySection

    var body: some View {
        Menu {
            Picker("Library section", selection: $selection) {
                ForEach(LibrarySection.allCases) { section in
                    Label(section.label, systemImage: section.symbol).tag(section)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Library section", systemImage: selection.symbol)
        }
        .accessibilityValue(selection.label)
        .accessibilityHint("Switches between titles, lists, and history")
        .accessibilityIdentifier("library.section-menu")
    }
}

/// One flat row of text chips, every shelf reachable in a single tap.
///
/// The old row was four glass buttons plus an ellipsis menu. Each button carried an icon,
/// a label and a glass background over a 44pt target, so four of them filled the width
/// before the fifth control — a menu — hid Caught Up and Dropped behind a second tap and
/// a label that changed identity depending on what was selected. Dropping the icons is
/// what buys the space back: the words already say what the shelves are, and without them
/// all six fit as chips at a size that reads as a filter bar rather than a toolbar. The
/// count carries the information the icon never did, and shelves that are empty say so by
/// not showing one.
private struct LibraryShelfPicker: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var selection: LibraryShelf
    let titles: [MediaTitle]

    var body: some View {
        HorizontalShelf(
            showsIndicators: dynamicTypeSize.isAccessibilitySize,
            snapsToItems: dynamicTypeSize.isAccessibilitySize
        ) {
            HStack(spacing: 8) {
                ForEach(LibraryShelf.allCases) { shelf in
                    if dynamicTypeSize.isAccessibilitySize {
                        chip(for: shelf)
                            .containerRelativeFrame(.horizontal) { width, _ in
                                accessiblePageWidth(for: width)
                            }
                    } else {
                        chip(for: shelf)
                    }
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, AppTheme.horizontalPadding)
            .padding(.vertical, 2)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Library shelves")
    }

    private func accessiblePageWidth(for proposedWidth: CGFloat) -> CGFloat {
        let minimumWidth = AppAccessibility.minimumTouchTarget
        let horizontalInset = AppTheme.horizontalPadding * 2

        guard proposedWidth.isFinite,
              horizontalInset.isFinite,
              proposedWidth > horizontalInset else {
            return minimumWidth
        }

        return max(minimumWidth, proposedWidth - horizontalInset)
    }

    private func chip(for shelf: LibraryShelf) -> some View {
        let isSelected = selection == shelf
        let count = titles.count(where: shelf.includes)

        return Button {
            selection = shelf
        } label: {
            HStack(spacing: 6) {
                Text(shelf.label)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)

                if count > 0 {
                    Text(count.formatted())
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? .black.opacity(0.55) : .secondary)
                }
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(.black) : AnyShapeStyle(.primary))
            .padding(.horizontal, 14)
            // Chips are wider than they are tall, so height is what the touch target has
            // to be argued about — hence a minimum height rather than the square
            // `minimumTouchTarget()` used by icon-only controls.
            .frame(minHeight: AppAccessibility.minimumTouchTarget)
            .background {
                Capsule().fill(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.quaternary))
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count > 0 ? "\(shelf.label), \(count)" : shelf.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("library.shelf.\(shelf.rawValue)")
    }
}

private struct LibraryTitlesView: View {
    let titles: [MediaTitle]
    let shelf: LibraryShelf
    let onOpenDiscover: () -> Void
    let onSelectShelf: (LibraryShelf) -> Void

    var body: some View {
        if titles.isEmpty {
            ContentUnavailableView {
                Label(shelf.emptyTitle, systemImage: shelf.symbol)
            } description: {
                Text(shelf.emptyDescription)
            } actions: {
                Button(shelf.emptyActionTitle, systemImage: emptyActionSymbol, action: emptyAction)
                    .adaptiveGlassButton(prominent: true)
            }
            .frame(maxHeight: .infinity)
        } else {
            List(titles) { title in
                NavigationLink(value: title) {
                    LibraryRow(title: title)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private var emptyActionSymbol: String {
        shelf.emptyActionShelf == nil ? "magnifyingglass" : "play.circle"
    }

    private func emptyAction() {
        if let destination = shelf.emptyActionShelf {
            onSelectShelf(destination)
        } else {
            onOpenDiscover()
        }
    }
}

struct LibraryRow: View {
    let title: MediaTitle

    var body: some View {
        HStack(spacing: 14) {
            PosterArtwork(title: title, cornerRadius: 10)
                .frame(width: 70, height: 96)

            VStack(alignment: .leading, spacing: 6) {
                Text(title.title)
                    .font(.headline)
                Text("\(title.displayYear) · \(title.kind.label)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Label(title.progressLabel, systemImage: title.state.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                if let progress = title.progress {
                    ProgressView(value: progress.fraction)
                        .tint(.accentColor)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    LibraryView(selectedTab: .constant(.library))
        .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
        .environment(\.allowsRemoteArtwork, false)
}
