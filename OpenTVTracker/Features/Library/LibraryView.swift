import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var filter: WatchState = .watching
    @State private var showsDataTools = false

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackdrop()

                VStack(spacing: 12) {
                    Picker("Library section", selection: $filter) {
                        ForEach(WatchState.allCases, id: \.self) { state in
                            Text(state.label).tag(state)
                        }
                    }
                    .pickerStyle(.segmented)
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
                .padding(.top, 8)
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ViewingAnalyticsView()
                    } label: {
                        Label("Viewing analytics", systemImage: "chart.bar.xaxis")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Import or export", systemImage: "arrow.up.arrow.down") {
                        showsDataTools = true
                    }
                }
            }
            .sheet(isPresented: $showsDataTools) {
                LibraryDataView()
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

private struct LibraryRow: View {
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
                Label(title.progressLabel, systemImage: title.state == .completed ? "checkmark.circle.fill" : "play.circle.fill")
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
    LibraryView()
        .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
        .environment(\.allowsRemoteArtwork, false)
}
