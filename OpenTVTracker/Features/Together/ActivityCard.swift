import SwiftUI

struct ActivityCard: View {
    @Environment(AppModel.self) private var model
    @State private var revealsReactions = false
    let activity: SharedActivity
    let space: SharedSpace
    let title: MediaTitle?

    var body: some View {
        GlassSurface(cornerRadius: AppTheme.compactRadius, tint: cardTint) {
            mediaContent
                .padding(12)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var mediaContent: some View {
        if let title {
            HStack(spacing: 10) {
                NavigationLink(value: title) {
                    HStack(spacing: 14) {
                        PosterArtwork(title: title, cornerRadius: 10)
                            .frame(width: 66, height: 92)
                            .clipped()
                            .clipShape(.rect(cornerRadius: 10))
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(title.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)

                            Text(activitySummary(for: title))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)

                            Label("\(member.name) · \(activity.relativeDate)", systemImage: activity.symbol)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens \(title.title)")

                reactionControl
            }
        } else {
            HStack(spacing: 14) {
                Image(systemName: activity.symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 70, height: 70)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityHidden(true)

                Text(activity.description)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                reactionControl
            }
        }
    }

    @ViewBuilder
    private var reactionControl: some View {
        if canViewReactions {
            Menu {
                ForEach(availableReactionAssets) { asset in
                    Button(
                        asset.kind == .gif ? "GIF: \(asset.label)" : "\(asset.displayValue) \(asset.label)"
                    ) {
                        addReaction(asset)
                    }
                }
            } label: {
                VStack(spacing: 4) {
                    if currentReactionAsset?.kind == .gif {
                        Text("GIF")
                            .font(.caption2.weight(.black))
                    } else {
                        Text(currentReactionAsset?.displayValue ?? "☺️")
                            .font(.body)
                    }
                    if !reactionCounts.isEmpty {
                        Text(reactionCounts.reduce(0) { $0 + $1.count }, format: .number)
                            .font(.caption2.weight(.semibold))
                    }
                }
                .foregroundStyle(currentReaction == nil ? Color.secondary : Color.accentColor)
                .frame(width: 44, height: 44)
            }
            .accessibilityLabel(currentReaction == nil ? "React to activity" : "Change reaction")
        } else {
            Button {
                revealsReactions = true
            } label: {
                Image(systemName: "eye.slash.fill")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Reveal spoiler-sensitive reactions")
            .accessibilityHint("Shows reactions attached to this episode")
        }
    }

    private var availableReactionAssets: [SharedReactionAsset] {
        activity.watchEventID == nil
            ? SharedReactionAssetPolicy.emojiAssets
            : SharedReactionAssetPolicy.allAssets
    }

    private var canViewReactions: Bool {
        guard let season = activity.season,
              let episode = activity.episode else {
            return true
        }
        guard let title,
              let episodeID = title.seasons?
                .first(where: { $0.number == season })?
                .episodes.first(where: { $0.number == episode })?
                .id else {
            return revealsReactions
        }
        return revealsReactions || model.isEpisodeWatched(
            titleID: title.id,
            seasonNumber: season,
            episodeID: episodeID
        )
    }

    private func addReaction(_ asset: SharedReactionAsset) {
        if let watchEventID = activity.watchEventID {
            model.react(to: watchEventID, asset: asset)
        } else {
            model.react(to: activity.id, symbol: asset.displayValue)
        }
    }

    private var currentReactionAsset: SharedReactionAsset? {
        currentReaction.flatMap(SharedReactionAssetPolicy.asset)
    }

    private var member: SpaceMember {
        space.members.first(where: { $0.id == activity.memberID })
            ?? SpaceMember(id: activity.memberID, name: "Someone", initials: "?", isCurrentUser: false)
    }

    private var currentReaction: SharedReaction? {
        let currentMemberID = space.members.first(where: \.isCurrentUser)?.id
        if let watchEventID = activity.watchEventID {
            return model.sharedSpace.reactions?.last { reaction in
                reaction.watchEventID == watchEventID && reaction.memberID == currentMemberID
            }
        }
        return model.sharedSpace.reactions?.last { reaction in
            reaction.activityID == activity.id && reaction.memberID == currentMemberID
        }
    }

    private var reactionCounts: [ActivityReactionCount] {
        let reactions = model.sharedSpace.reactions?.filter { reaction in
            if let watchEventID = activity.watchEventID {
                return reaction.watchEventID == watchEventID
            }
            return reaction.activityID == activity.id
        } ?? []
        return Dictionary(grouping: reactions) { reaction in
            SharedReactionAssetPolicy.asset(for: reaction)?.id ?? reaction.symbol
        }
            .map { ActivityReactionCount(assetID: $0.key, count: $0.value.count) }
            .sorted { $0.assetID < $1.assetID }
    }

    private var cardTint: Color? {
        title.map { Color(hex: $0.palette.primaryHex) }
    }

    private func activitySummary(for title: MediaTitle) -> String {
        activity.description.replacingOccurrences(
            of: title.title,
            with: "",
            options: [.caseInsensitive]
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .capitalized
    }
}

private struct ActivityReactionCount: Identifiable {
    let assetID: String
    let count: Int
    var id: String { assetID }
}
