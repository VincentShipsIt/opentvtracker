import SwiftUI

struct ActivityCard: View {
    @Environment(AppModel.self) private var model
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

                reactionMenu
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

                reactionMenu
            }
        }
    }

    private var reactionMenu: some View {
        Menu {
            Button("Love", systemImage: "heart.fill") {
                model.react(to: activity.id, symbol: "heart.fill")
            }
            Button("Nice", systemImage: "hand.thumbsup.fill") {
                model.react(to: activity.id, symbol: "hand.thumbsup.fill")
            }
            Button("Funny", systemImage: "face.smiling.fill") {
                model.react(to: activity.id, symbol: "face.smiling.fill")
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: reactionSymbol)
                    .font(.body.weight(.semibold))
                if !reactionCounts.isEmpty {
                    Text(reactionCounts.reduce(0) { $0 + $1.count }, format: .number)
                        .font(.caption2.weight(.semibold))
                }
            }
            .foregroundStyle(currentReaction == nil ? Color.secondary : Color.accentColor)
            .frame(width: 44, height: 44)
        }
        .accessibilityLabel(currentReaction == nil ? "React to activity" : "Change reaction")
    }

    private var member: SpaceMember {
        space.members.first(where: { $0.id == activity.memberID })
            ?? SpaceMember(id: activity.memberID, name: "Someone", initials: "?", isCurrentUser: false)
    }

    private var currentReaction: SharedReaction? {
        let currentMemberID = space.members.first(where: \.isCurrentUser)?.id
        return model.sharedSpace.reactions?.last { reaction in
            reaction.activityID == activity.id && reaction.memberID == currentMemberID
        }
    }

    private var reactionSymbol: String {
        currentReaction?.symbol ?? "face.smiling"
    }

    private var reactionCounts: [ActivityReactionCount] {
        let reactions = model.sharedSpace.reactions?.filter { $0.activityID == activity.id } ?? []
        return Dictionary(grouping: reactions, by: \.symbol)
            .map { ActivityReactionCount(symbol: $0.key, count: $0.value.count) }
            .sorted { $0.symbol < $1.symbol }
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
    let symbol: String
    let count: Int
    var id: String { symbol }
}
