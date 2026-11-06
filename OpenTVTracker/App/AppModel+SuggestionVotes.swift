import Foundation

extension AppModel {
    var suggestionVoteBoard: SuggestionVoteBoard {
        SuggestionVoteBoard(
            votes: sharedSpace.suggestionVotes ?? [],
            currentMemberID: currentMemberID
        )
    }

    var hasSharingPartner: Bool {
        sharedSpace.members.contains { !$0.isCurrentUser }
    }

    /// The three starter cards for the chat home screen. With a partner connected they
    /// favour picks that suit both tastes.
    var dailySuggestionCards: [DiscoveryAssistantMatch] {
        DiscoveryAssistantEngine.suggestions(
            titles: discoverableTitles,
            selectedProviderIDs: selectedProviderIDs,
            tasteProfiles: sharedSpace.tasteProfiles ?? [],
            count: 3,
            forBothMembers: hasSharingPartner
        )
    }

    /// Records the current member's vote on a title and shares it with the partner.
    /// Changing your mind replaces the earlier vote.
    func castSuggestionVote(_ choice: SuggestionVoteChoice, for titleID: MediaTitle.ID, at date: Date = .now) {
        let memberID = currentMemberID
        var votes = sharedSpace.suggestionVotes ?? []
        votes.removeAll { $0.titleID == titleID && $0.memberID == memberID }
        votes.append(
            SharedSuggestionVote(
                titleID: titleID,
                memberID: memberID,
                choice: choice,
                votedAt: date
            )
        )
        sharedSpace.suggestionVotes = votes
        prepareSharedTitleMetadataForSync()
        persist()
        syncSharedStateSoon()
    }
}
