import SwiftUI

struct ActivityCard: View {
    @Environment(AppModel.self) private var model
    let activity: SharedActivity
    let space: SharedSpace
    let title: MediaTitle?

    var body: some View {
        GlassSurface(cornerRadius: AppTheme.compactRadius, tint: cardTint) {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 14)
                    .padding(.top, 12)

                Divider()
                    .padding(.top, 10)

                mediaContent
                    .padding(12)

                Divider()

                reactionBar
                    .padding(.horizontal, 14)
                    .frame(minHeight: 50)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(spacing: 9) {
            Text(member.initials)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Color.accentColor.gradient, in: Circle())
                .accessibilityHidden(true)

            Text(member.name)
                .font(.subheadline.weight(.semibold))

            Spacer(minLength: 8)

            Label(activity.relativeDate, systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var mediaContent: some View {
        if let title {
            NavigationLink(value: title) {
                HStack(spacing: 14) {
                    PosterArtwork(title: title, cornerRadius: 10)
                        .frame(width: 70, height: 96)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 7) {
                        Text(activity.description)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)

                        Text(verbatim: metadata(for: title))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let provider = title.providers.first {
                            Label(provider.name, systemImage: provider.symbol)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(cardTint ?? Color.accentColor)
                        } else if let genre = title.genres.first {
                            Label(genre, systemImage: "tag.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(cardTint ?? Color.accentColor)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens \(title.title)")
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
            }
        }
    }

    private var reactionBar: some View {
        HStack(spacing: 12) {
            if reactionCounts.isEmpty {
                Text("Be the first to react")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(reactionCounts) { reaction in
                    Label("\(reaction.count)", systemImage: reaction.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

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
                Label(currentReaction == nil ? "React" : "Reacted", systemImage: reactionSymbol)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
            .accessibilityLabel(currentReaction == nil ? "React to activity" : "Change reaction")
        }
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

    private func metadata(for title: MediaTitle) -> String {
        var values = [String(title.year), title.kind.label]
        if title.runtimeMinutes > 0 {
            values.append("\(title.runtimeMinutes) min")
        }
        return values.joined(separator: " · ")
    }
}

private struct ActivityReactionCount: Identifiable {
    let symbol: String
    let count: Int
    var id: String { symbol }
}
