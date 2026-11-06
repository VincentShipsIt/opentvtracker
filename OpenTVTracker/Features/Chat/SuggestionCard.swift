import SwiftUI

/// A suggested title with Yes / Maybe / Pass buttons. When a partner is connected the card
/// also says where the two of you stand, so a suggestion can be settled without a chat.
struct SuggestionCard: View {
    let match: DiscoveryAssistantMatch
    let board: SuggestionVoteBoard
    let partnerName: String?
    let onVote: (SuggestionVoteChoice) -> Void

    private var titleID: MediaTitle.ID { match.title.id }

    var body: some View {
        GlassSurface(cornerRadius: AppTheme.compactRadius, tint: Color(hex: match.title.palette.primaryHex)) {
            VStack(alignment: .leading, spacing: 12) {
                NavigationLink(value: match.title) {
                    header
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens details")

                voteButtons

                if let status = SuggestionCardStatus.text(
                    verdict: board.verdict(for: titleID),
                    partnerChoice: board.partnerChoice(for: titleID),
                    partnerName: partnerName
                ) {
                    Label(status.text, systemImage: status.symbol)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(status.isPositive ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .accessibilityIdentifier("suggestion.status.\(titleID)")
                }
            }
            .padding(12)
        }
        .accessibilityIdentifier("suggestion.card.\(titleID)")
    }

    private var header: some View {
        HStack(spacing: 14) {
            PosterArtwork(title: match.title, cornerRadius: 10)
                .frame(width: 82, height: 120)

            VStack(alignment: .leading, spacing: 7) {
                Text(match.title.title)
                    .font(.title3.weight(.bold))
                    .lineLimit(2)

                HStack(spacing: 8) {
                    RatingLabel(rating: match.title.rating)
                    Text("\(match.title.runtimeMinutes) min")
                    if let provider = match.title.providers.first {
                        Text(provider.name)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                Text(match.reason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    private var voteButtons: some View {
        HStack(spacing: 8) {
            ForEach(SuggestionVoteChoice.allCases, id: \.self) { choice in
                let isSelected = board.myChoice(for: titleID) == choice
                Button {
                    onVote(choice)
                } label: {
                    Label(choice.label, systemImage: choice.symbol)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(isSelected ? .accentColor : .secondary)
                .minimumTouchTarget()
                .accessibilityLabel("\(choice.label) for \(match.title.title)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("suggestion.vote.\(choice.rawValue).\(titleID)")
            }
        }
    }
}

/// The one-line summary under a card's buttons.
enum SuggestionCardStatus {
    struct Line: Equatable {
        let text: String
        let symbol: String
        let isPositive: Bool
    }

    static func text(
        verdict: SuggestionVerdict,
        partnerChoice: SuggestionVoteChoice?,
        partnerName: String?
    ) -> Line? {
        guard let partnerName else { return nil }
        switch verdict {
        case .open:
            return nil
        case .waitingForPartner:
            return Line(text: "Waiting for \(partnerName)", symbol: "hourglass", isPositive: false)
        case .waitingForYou:
            let choice = partnerChoice == .like ? "wants to watch this" : "might watch this"
            return Line(text: "\(partnerName) \(choice)", symbol: "person.fill.questionmark", isPositive: true)
        case .match:
            return Line(text: "You both said yes", symbol: "heart.fill", isPositive: true)
        case .passed:
            return Line(text: "Not this time", symbol: "xmark.circle", isPositive: false)
        case .undecided:
            return Line(text: "Still deciding together", symbol: "ellipsis.bubble", isPositive: false)
        }
    }
}
