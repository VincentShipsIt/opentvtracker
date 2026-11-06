import Foundation

/// How one member felt about a suggested title.
enum SuggestionVoteChoice: String, Codable, CaseIterable, Sendable {
    case like
    case maybe
    case pass

    var label: String {
        switch self {
        case .like: "Yes"
        case .maybe: "Maybe"
        case .pass: "Pass"
        }
    }

    var symbol: String {
        switch self {
        case .like: "hand.thumbsup.fill"
        case .maybe: "questionmark.circle.fill"
        case .pass: "hand.thumbsdown.fill"
        }
    }
}

/// One member's vote on one title. Stored inside the shared space payload, so it needs no
/// new CloudKit record type. A member has at most one vote per title; the latest wins.
struct SharedSuggestionVote: Codable, Hashable, Identifiable, Sendable {
    let titleID: MediaTitle.ID
    let memberID: SpaceMember.ID
    var choice: SuggestionVoteChoice
    var votedAt: Date

    var id: String { Self.id(titleID: titleID, memberID: memberID) }

    static func id(titleID: MediaTitle.ID, memberID: SpaceMember.ID) -> String {
        "\(memberID):\(titleID)"
    }
}

enum SuggestionVoteReconciler {
    /// Keeps the most recent vote per member and title, so either device can change its mind.
    static func merge(
        remote: [SharedSuggestionVote],
        local: [SharedSuggestionVote]
    ) -> [SharedSuggestionVote] {
        var votesByID: [String: SharedSuggestionVote] = [:]
        for vote in remote + local {
            if let existing = votesByID[vote.id], existing.votedAt > vote.votedAt {
                continue
            }
            votesByID[vote.id] = vote
        }
        return votesByID.values.sorted { ($0.votedAt, $0.id) < ($1.votedAt, $1.id) }
    }
}

/// Where a title stands between two people.
enum SuggestionVerdict: Equatable, Sendable {
    /// Nobody has voted yet.
    case open
    case waitingForPartner
    case waitingForYou
    /// Both said yes.
    case match
    /// Somebody passed, so it is off the table.
    case passed
    /// Both voted and at least one is unsure.
    case undecided
}

/// A read-only view of the votes from the current member's point of view.
struct SuggestionVoteBoard: Equatable, Sendable {
    let votes: [SharedSuggestionVote]
    let currentMemberID: SpaceMember.ID

    func myChoice(for titleID: MediaTitle.ID) -> SuggestionVoteChoice? {
        latestVote(for: titleID) { $0.memberID == currentMemberID }?.choice
    }

    func partnerChoice(for titleID: MediaTitle.ID) -> SuggestionVoteChoice? {
        latestVote(for: titleID) { $0.memberID != currentMemberID }?.choice
    }

    func verdict(for titleID: MediaTitle.ID) -> SuggestionVerdict {
        switch (myChoice(for: titleID), partnerChoice(for: titleID)) {
        case (nil, nil): .open
        case (.some, nil): .waitingForPartner
        case (nil, .some): .waitingForYou
        case (.like, .like): .match
        case (.pass, _), (_, .pass): .passed
        default: .undecided
        }
    }

    /// Titles both members liked, newest agreement first.
    var matchedTitleIDs: [MediaTitle.ID] {
        let candidates = Set(votes.map(\.titleID))
        return candidates
            .filter { verdict(for: $0) == .match }
            .sorted { agreementDate(for: $0) > agreementDate(for: $1) }
    }

    /// Titles the partner voted yes or maybe on that the current member has not answered.
    var awaitingMyAnswerTitleIDs: [MediaTitle.ID] {
        let candidates = Set(votes.map(\.titleID))
        return candidates
            .filter { verdict(for: $0) == .waitingForYou && partnerChoice(for: $0) != .pass }
            .sorted()
    }

    private func latestVote(
        for titleID: MediaTitle.ID,
        where belongs: (SharedSuggestionVote) -> Bool
    ) -> SharedSuggestionVote? {
        votes
            .filter { $0.titleID == titleID && belongs($0) }
            .max { $0.votedAt < $1.votedAt }
    }

    private func agreementDate(for titleID: MediaTitle.ID) -> Date {
        votes
            .filter { $0.titleID == titleID }
            .map(\.votedAt)
            .max() ?? .distantPast
    }
}
