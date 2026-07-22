import SwiftUI

struct LibraryHistoryView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(BackupHealth.lastSuccessfulExportTimestampKey)
    private var lastSuccessfulBackupTimestamp = 0.0
    let onOpenDiscover: () -> Void
    let onOpenDataTools: () -> Void

    var body: some View {
        let diaryRecords = model.diaryRecords
        let summary = ViewingAnalyticsEngine.summarize(snapshot: model.snapshot, scope: .personal)

        ScrollView {
            LazyVStack(spacing: AppTheme.sectionSpacing) {
                LibraryPrivacyHeader(member: currentMember)

                if diaryRecords.isEmpty, summary.isEmpty {
                    ContentUnavailableView {
                        Label("No private history yet", systemImage: "clock.badge.questionmark")
                    } description: {
                        Text("Mark a movie or episode watched to build your diary and viewing statistics.")
                    } actions: {
                        Button("Find something to watch", systemImage: "magnifyingglass", action: onOpenDiscover)
                            .adaptiveGlassButton(prominent: true)
                    }
                }

                NavigationLink {
                    ViewingDiaryView()
                } label: {
                    ViewingDiaryPreviewCard(
                        entryCount: diaryRecords.count,
                        latestDate: diaryRecords.first?.entry.watchedAt
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("library.viewing-diary")

                NavigationLink {
                    ViewingAnalyticsView(scope: .personal)
                } label: {
                    ViewingAnalyticsPreviewCard(summary: summary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("library.viewing-analytics")

                LibraryDataOwnershipCard(
                    backupHealth: backupHealth,
                    action: onOpenDataTools
                )
            }
            .padding(.horizontal, AppTheme.horizontalPadding)
            .padding(.bottom, 32)
        }
    }

    private var currentMember: SpaceMember {
        model.sharedSpace.members.first(where: \.isCurrentUser)
            ?? SpaceMember(id: "local-user", name: "You", initials: "YOU", isCurrentUser: true)
    }

    private var backupHealth: BackupHealthState {
        BackupHealth.state(
            lastSuccessfulExportAt: BackupHealth.lastSuccessfulExportAt(
                from: lastSuccessfulBackupTimestamp
            )
        )
    }
}

private struct LibraryPrivacyHeader: View {
    @ScaledMetric(relativeTo: .title2) private var avatarSize = 64.0
    let member: SpaceMember

    var body: some View {
        GlassSurface(tint: .indigo) {
            HStack(spacing: 16) {
                Text(member.initials)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .frame(width: avatarSize, height: avatarSize)
                    .background(Color.indigo.gradient, in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(member.name)
                        .font(.title2.weight(.bold))
                    Text("Your private viewing history")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Label("Visible only to you unless you export it", systemImage: "lock.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.indigo)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(18)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ViewingDiaryPreviewCard: View {
    let entryCount: Int
    let latestDate: Date?

    var body: some View {
        GlassSurface(tint: .purple) {
            HStack(spacing: 16) {
                Image(systemName: "calendar.badge.clock")
                    .font(.title)
                    .foregroundStyle(.purple)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Viewing diary")
                        .font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(16)
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        guard entryCount > 0 else { return "Private dates, ratings, notes, and rewatches" }
        guard let latestDate else { return "\(entryCount) private entries" }
        return "\(entryCount) entries · Latest \(latestDate.formatted(.relative(presentation: .named)))"
    }
}

private struct LibraryDataOwnershipCard: View {
    let backupHealth: BackupHealthState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GlassSurface(tint: .teal) {
                HStack(spacing: 16) {
                    Image(systemName: "externaldrive.fill.badge.plus")
                        .font(.title)
                        .foregroundStyle(.teal)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Import & export your data")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("Complete JSON backup, readable CSV files, and TV Time import")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Label(backupHealth.label, systemImage: backupHealth.systemImage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.teal)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .padding(16)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens labeled backup, import, and export actions")
        .accessibilityIdentifier("library.data-tools")
    }
}

#Preview {
    NavigationStack {
        LibraryHistoryView(onOpenDiscover: {}, onOpenDataTools: {})
            .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
    }
}
