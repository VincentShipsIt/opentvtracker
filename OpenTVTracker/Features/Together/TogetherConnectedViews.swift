import SwiftUI

struct TogetherSharedLibraryEmptyState: View {
    var body: some View {
        GlassSurface(tint: .indigo) {
            VStack(spacing: 16) {
                Image(systemName: "rectangle.stack.badge.plus")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                Text("Choose your first shared title")
                    .font(.title2.weight(.bold))
                Text("Add something from your library, then both members can see the shared queue and progress here.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                NavigationLink {
                    SharedTitlePickerView()
                } label: {
                    Label("Add a shared title", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .adaptiveGlassButton(prominent: true)
                .accessibilityIdentifier("together.add-shared-title")
            }
            .frame(maxWidth: .infinity)
            .padding(20)
        }
    }
}

struct TogetherSharedUpNextSection: View {
    @Environment(AppModel.self) private var model
    let title: MediaTitle
    let space: SharedSpace

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(
                title: "Shared up next",
                subtitle: title.nextReleaseDescription ?? "Your next shared pick"
            )

            NavigationLink(value: title) {
                GlassSurface(cornerRadius: AppTheme.compactRadius, tint: Color(hex: title.palette.primaryHex)) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 14) {
                            PosterArtwork(title: title, cornerRadius: 10)
                                .frame(width: 72, height: 102)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 6) {
                                Text(title.title)
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                Text(title.kind == .movie ? "Shared movie" : "Continue together")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                                Text(model.togetherProgressSummary(for: title).label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        VStack(spacing: 12) {
                            ForEach(space.members) { member in
                                TogetherMemberProgressRow(
                                    member: member,
                                    summary: model.togetherMemberProgressSummary(
                                        for: title,
                                        memberID: member.id
                                    )
                                )
                            }
                        }
                    }
                    .padding(14)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens \(title.title)")
            .accessibilityIdentifier("together.shared-title.\(title.id)")

            NavigationLink {
                SharedTitlePickerView()
            } label: {
                Label("Add another shared title", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .adaptiveGlassButton()
            .accessibilityIdentifier("together.add-shared-title")
        }
    }
}

private struct TogetherMemberProgressRow: View {
    let member: SpaceMember
    let summary: MediaProgressSummary

    var body: some View {
        HStack(spacing: 10) {
            Text(member.initials)
                .font(.caption2.weight(.bold))
                .minimumScaleFactor(0.7)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.16), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(member.isCurrentUser ? "You" : member.name)
                    .font(.subheadline.weight(.semibold))
                ProgressView(value: summary.fraction)
                    .tint(Color.accentColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(summary.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(member.isCurrentUser ? "You" : member.name), \(summary.label)")
    }
}

struct TogetherSharedWatchlistSection: View {
    @Environment(AppModel.self) private var model
    let titles: [MediaTitle]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(
                title: "Shared watchlist",
                subtitle: "\(titles.count) more \(titles.count == 1 ? "title" : "titles")"
            )

            LazyVStack(spacing: 12) {
                ForEach(titles) { title in
                    NavigationLink(value: title) {
                        MediaProgressRow(
                            title: title,
                            summary: model.togetherProgressSummary(for: title),
                            subtitle: sharedTitleSubtitle(for: title)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    private func sharedTitleSubtitle(for title: MediaTitle) -> String {
        if title.kind == .movie { return "Shared movie" }
        switch title.state {
        case .planned:
            return "Shared watchlist"
        case .caughtUp:
            return "Caught up together"
        case .paused, .dropped:
            return title.state == .paused ? "Paused together" : "Dropped together"
        default:
            return "Watching together"
        }
    }
}

struct TogetherRecentActivitySection: View {
    @Environment(AppModel.self) private var model
    let activities: [SharedActivity]
    let space: SharedSpace

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(
                title: "Recent activity",
                subtitle: "Private to this space · spoiler-safe by default"
            )

            LazyVStack(spacing: 12) {
                ForEach(activities) { activity in
                    ActivityCard(
                        activity: activity,
                        space: space,
                        title: model.mediaTitle(for: activity)
                    )
                }
            }
        }
    }
}

private struct SharedTitlePickerView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            AmbientBackdrop()

            if availableTitles.isEmpty {
                ContentUnavailableView(
                    "Your whole library is shared",
                    systemImage: "checkmark.circle.fill",
                    description: Text("Add more titles from Discover whenever you want another shared pick.")
                )
            } else {
                List(availableTitles) { title in
                    SharedTitlePickerRow(title: title)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Add shared titles")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var availableTitles: [MediaTitle] {
        model.titles
            .filter { !model.isShared($0.id) }
            .sorted { lhs, rhs in
                if (lhs.state == .watching) != (rhs.state == .watching) {
                    return lhs.state == .watching
                }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
    }
}

private struct SharedTitlePickerRow: View {
    @Environment(AppModel.self) private var model
    let title: MediaTitle

    var body: some View {
        HStack(spacing: 14) {
            PosterArtwork(title: title, cornerRadius: 10)
                .frame(width: 62, height: 88)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(title.title)
                    .font(.headline)
                    .lineLimit(2)
                Text("\(title.year) · \(title.kind.label) · \(title.state.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Add", systemImage: "plus") {
                model.toggleTogether(title.id)
            }
            .labelStyle(.iconOnly)
            .adaptiveGlassButton(prominent: true)
            .accessibilityLabel("Add \(title.title) to the shared watchlist")
        }
        .padding(.vertical, 4)
    }
}
