import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var section: LibrarySection = .titles
    @State private var filter: WatchState = .watching
    @State private var presentedSheet: LibrarySheet?

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackdrop()

                VStack(spacing: 12) {
                    Picker("Library view", selection: $section) {
                        ForEach(LibrarySection.allCases) { section in
                            Text(section.label).tag(section)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, AppTheme.horizontalPadding)

                    if section == .lists {
                        CustomListsView()
                    } else {
                        Picker("Tracking state", selection: $filter) {
                            ForEach(WatchState.allCases, id: \.self) { state in
                                Text(state.label).tag(state)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(.horizontal, AppTheme.horizontalPadding)

                        Group {
                            if filteredTitles.isEmpty {
                                ContentUnavailableView(
                                    "Nothing \(filter.label.lowercased())",
                                    systemImage: "rectangle.stack.badge.plus",
                                    description: Text("Add something from Discover and it will appear here.")
                                )
                                .frame(maxHeight: .infinity)
                            } else {
                                List(filteredTitles) { title in
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
                        .transaction { $0.disablesAnimations = true }
                    }
                }
                .padding(.top, 8)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Profile and settings", systemImage: "person.crop.circle") {
                        presentedSheet = .profile
                    }
                    .accessibilityHint("Opens your viewing profile and app settings")
                    .accessibilityIdentifier("library.profile")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Import or export", systemImage: "arrow.up.arrow.down") {
                        presentedSheet = .dataTools
                    }
                }
            }
            .sheet(item: $presentedSheet) { sheet in
                switch sheet {
                case .dataTools:
                    LibraryDataView()
                case .profile:
                    ProfileView()
                }
            }
            .navigationDestination(for: MediaTitle.self) { title in
                MediaDetailView(titleID: title.id)
            }
        }
    }

    private var filteredTitles: [MediaTitle] {
        model.titles(in: filter)
    }
}

private enum LibrarySheet: String, Identifiable {
    case dataTools
    case profile

    var id: Self { self }
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

private enum LibrarySection: String, CaseIterable, Identifiable {
    case titles
    case lists

    var id: Self { self }

    var label: String {
        switch self {
        case .titles: "Titles"
        case .lists: "Lists"
        }
    }
}

#Preview {
    LibraryView()
        .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
        .environment(\.allowsRemoteArtwork, false)
}
