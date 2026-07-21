import SwiftUI

struct TraktSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var authorization: TraktDeviceAuthorization?
    @State private var isAuthorizing = false
    @State private var authorizationError: String?

    var body: some View {
        Form {
            connectionSection

            if model.isTraktAuthorized {
                syncSection
            }

            mappingSection
        }
        .task { await model.refreshTraktAuthorizationStatus() }
        .navigationTitle("Trakt sync")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var connectionSection: some View {
        Section {
            LabeledContent(
                "Status",
                value: model.isTraktAuthorized ? "Connected" : "Not connected"
            )

            if model.isTraktAuthorized {
                Button("Disconnect Trakt", role: .destructive) {
                    Task { await model.disconnectTrakt() }
                }
                .disabled(model.isTraktSyncing)
            } else if let authorization {
                LabeledContent("Activation code") {
                    Text(authorization.userCode)
                        .font(.body.monospaced().bold())
                        .textSelection(.enabled)
                }
                Link("Open Trakt activation", destination: authorization.activationURL)
                if isAuthorizing {
                    ProgressView("Waiting for Trakt authorization…")
                }
            } else {
                Button("Connect Trakt") {
                    Task { await connect() }
                }
                .disabled(isAuthorizing)
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Trakt error: \(errorMessage)")
            }
        } header: {
            Text("Account")
        } footer: {
            Text("Device authorization opens Trakt in your browser. Access and refresh tokens stay in this iPhone's Keychain.")
        }
    }

    private var syncSection: some View {
        Section {
            if let lastSyncedAt = model.traktSyncState.lastSyncedAt {
                LabeledContent("Last sync") {
                    Text(lastSyncedAt, format: .relative(presentation: .named))
                }
            } else {
                LabeledContent("Last sync", value: "Never")
            }
            LabeledContent("Pending local changes", value: "\(model.traktPendingChangeCount)")
            LabeledContent("Imported lists", value: "\(model.traktSyncState.importedLists.count)")

            Button("Sync now", systemImage: "arrow.triangle.2.circlepath") {
                Task { await model.syncTrakt() }
            }
            .disabled(model.isTraktSyncing)

            if model.isTraktSyncing {
                ProgressView("Syncing without blocking your local library…")
            }
            if let traktSyncSummary = model.traktSyncSummary {
                Text(traktSyncSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Two-way sync")
        } footer: {
            Text("OpenTV checks Trakt activity timestamps before pulling. Offline or provider failures leave your local library unchanged and keep local changes pending.")
        }
    }

    private var mappingSection: some View {
        Section {
            LabeledContent("History", value: "movies and episodes")
            LabeledContent("Ratings", value: "movie and show")
            LabeledContent("Watchlist", value: "two-way")
            LabeledContent("Personal lists", value: "membership preserved")
            NavigationLink("Exact field mapping") {
                TraktFieldMappingView()
            }
        } header: {
            Text("Portable data")
        } footer: {
            Text("Local progress never moves backward. When both sides changed a rating, OpenTV keeps the local value.")
        }
    }

    private var errorMessage: String? {
        authorizationError ?? model.traktSyncError ?? model.traktSyncState.lastError
    }

    private func connect() async {
        isAuthorizing = true
        authorizationError = nil
        defer { isAuthorizing = false }

        do {
            let request = try await model.beginTraktAuthorization()
            authorization = request
            openURL(request.activationURL)
            try await model.completeTraktAuthorization(request)
            authorization = nil
            await model.syncTrakt()
        } catch {
            authorization = nil
            authorizationError = error.localizedDescription
        }
    }
}

private struct TraktFieldMappingView: View {
    var body: some View {
        List {
            Section("Imported and synced") {
                Text("TMDB IDs match movies and shows.")
                Text("Movie watches and episode season/number pairs merge into local history.")
                Text("Title ratings use Trakt's 1–10 integer scale.")
                Text("Watchlist membership uses a three-way merge.")
                Text("Personal list names and TMDB memberships are retained in the portable backup.")
            }

            Section("Kept local") {
                Text("Private notes, partner activity, moods, provider choices, recommendation feedback, and exact fractional ratings never leave OpenTV.")
                Text("Episode ratings, list notes, list rank, playback percentage, and Trakt social activity have no OpenTV equivalent.")
            }
        }
        .navigationTitle("Trakt field mapping")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        TraktSettingsView()
            .environment(AppModel(
                store: MemoryLibraryStore(),
                traktService: UnconfiguredTraktSyncService(),
                seed: .sample
            ))
    }
}
