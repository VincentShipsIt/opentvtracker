import SwiftUI

/// One exchange in the chat: what you asked, what came back.
struct ChatTurnView: View {
    let turn: DiscoveryConversationTurn
    let board: SuggestionVoteBoard
    let partnerName: String?
    let onVote: (SuggestionVoteChoice, MediaTitle.ID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(turn.prompt)
                .font(.body)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.tint.opacity(0.22), in: .rect(cornerRadius: 18))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel("You asked: \(turn.prompt)")

            Text(turn.response.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("chat.reply.\(turn.id)")

            ForEach(turn.response.matches) { match in
                SuggestionCard(
                    match: match,
                    board: board,
                    partnerName: partnerName,
                    onVote: { onVote($0, match.title.id) }
                )
            }
        }
    }
}

/// Picks your partner voted on that are still waiting for your answer, and the ones you
/// both said yes to.
struct ChatPartnerVotesSection: View {
    let board: SuggestionVoteBoard
    let partnerName: String?
    let titleLookup: (MediaTitle.ID) -> MediaTitle?
    let onVote: (SuggestionVoteChoice, MediaTitle.ID) -> Void

    var body: some View {
        if partnerName != nil {
            let matches = resolved(board.matchedTitleIDs, reason: "You both said yes.")
            let waiting = resolved(
                board.awaitingMyAnswerTitleIDs,
                reason: "\(partnerName ?? "Your partner") voted on this."
            )

            if !matches.isEmpty {
                section("You both said yes", matches: matches)
            }
            if !waiting.isEmpty {
                section("Waiting for your answer", matches: waiting)
            }
        }
    }

    private func section(_ heading: String, matches: [DiscoveryAssistantMatch]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(heading)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            ForEach(matches) { match in
                SuggestionCard(
                    match: match,
                    board: board,
                    partnerName: partnerName,
                    onVote: { onVote($0, match.title.id) }
                )
            }
        }
    }

    private func resolved(_ ids: [MediaTitle.ID], reason: String) -> [DiscoveryAssistantMatch] {
        ids.compactMap(titleLookup).map {
            DiscoveryAssistantMatch(title: $0, reason: reason, score: 0)
        }
    }
}
