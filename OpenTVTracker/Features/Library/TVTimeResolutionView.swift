import SwiftUI

struct ImportResolutionSection: View {
    let issues: [ImportResolutionIssue]
    let coordinator: TVTimeImportCoordinator

    var body: some View {
        Section {
            ForEach(issues) { issue in
                NavigationLink {
                    TVTimeResolutionView(issue: issue, coordinator: coordinator)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(issue.displayTitle)
                            .foregroundStyle(.primary)
                        Text([
                            issue.kind.label,
                            issue.year.map { String($0) },
                            issue.reason.label
                        ].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(issue.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        } header: {
            Text("Needs a catalog match")
        } footer: {
            Text("Choose the correct release once. OpenTV saves the source-ID mapping for safe re-imports.")
        }
    }
}

private struct TVTimeResolutionView: View {
    @Environment(\.dismiss) private var dismiss
    let issue: ImportResolutionIssue
    let coordinator: TVTimeImportCoordinator
    @State private var query: String
    @State private var results: [MediaTitle] = []
    @State private var isSearching = false

    init(issue: ImportResolutionIssue, coordinator: TVTimeImportCoordinator) {
        self.issue = issue
        self.coordinator = coordinator
        _query = State(initialValue: issue.title)
    }

    var body: some View {
        List {
            Section {
                LabeledContent("From TV Time", value: issue.displayTitle)
                LabeledContent("Type", value: issue.kind.label)
                if let year = issue.year {
                    LabeledContent("Year", value: String(year))
                }
                Text(issue.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Catalog matches") {
                if isSearching {
                    ProgressView("Searching catalog…")
                } else if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          let errorMessage = coordinator.errorMessage {
                    ContentUnavailableView(
                        "Catalog unavailable",
                        systemImage: "wifi.exclamationmark",
                        description: Text(errorMessage)
                    )
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    ForEach(results) { title in
                        Button {
                            Task {
                                if await coordinator.resolve(issue, with: title) {
                                    dismiss()
                                }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: title.kind.symbol)
                                    .frame(width: 32, height: 32)
                                    .foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(title.title)
                                        .foregroundStyle(.primary)
                                    Text("\(title.year) · \(title.kind.label)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(coordinator.isRefreshing)
                    }
                }
            }
        }
        .navigationTitle("Resolve title")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search the catalog")
        .task(id: query) {
            await search()
        }
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            return
        }
        isSearching = true
        defer { isSearching = false }
        do {
            try await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let newResults = await coordinator.search(trimmed, kind: issue.kind)
            guard !Task.isCancelled else { return }
            results = newResults
        } catch is CancellationError {
            return
        } catch {
            results = []
        }
    }
}
