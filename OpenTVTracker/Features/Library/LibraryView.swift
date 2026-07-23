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

                VStack(spacing: 12) {
                    LibrarySectionPicker(selection: $section)

                    switch section {
                    case .titles:
                        LibraryShelfPicker(selection: $shelf)
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
                .padding(.top, 8)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
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

    static let primary: [LibraryShelf] = [.keepWatching, .watchlist, .paused, .completed]
    static let secondary: [LibraryShelf] = [.caughtUp, .dropped]

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

private struct LibrarySectionPicker: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var selection: LibrarySection

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Picker("Library section", selection: $selection) {
                ForEach(LibrarySection.allCases) { section in
                    Label(section.label, systemImage: section.symbol).tag(section)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppTheme.horizontalPadding)
        } else {
            Picker("Library section", selection: $selection) {
                ForEach(LibrarySection.allCases) { section in
                    Text(section.label).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, AppTheme.horizontalPadding)
        }
    }
}

private struct LibraryShelfPicker: View {
    @Binding var selection: LibraryShelf

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(LibraryShelf.primary) { shelf in
                    Button {
                        selection = shelf
                    } label: {
                        Label(shelf.label, systemImage: shelf.symbol)
                            .lineLimit(1)
                    }
                    .adaptiveGlassButton(prominent: selection == shelf)
                    .accessibilityAddTraits(selection == shelf ? .isSelected : [])
                }

                Menu {
                    ForEach(LibraryShelf.secondary) { shelf in
                        Button {
                            selection = shelf
                        } label: {
                            Label(shelf.label, systemImage: shelf.symbol)
                        }
                    }
                } label: {
                    Label(moreLabel, systemImage: "ellipsis.circle")
                        .lineLimit(1)
                }
                .adaptiveGlassButton(prominent: LibraryShelf.secondary.contains(selection))
            }
            .padding(.horizontal, AppTheme.horizontalPadding)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Library shelves")
    }

    private var moreLabel: String {
        LibraryShelf.secondary.contains(selection) ? selection.label : "More"
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
                Text("\(title.year) · \(title.kind.label)")
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
