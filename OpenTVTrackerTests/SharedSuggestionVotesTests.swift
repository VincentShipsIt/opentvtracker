import XCTest
@testable import OpenTVTracker

@MainActor
final class SharedSuggestionVotesTests: XCTestCase {
    private let viewer = "viewer"
    private let partner = "partner"
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func vote(
        _ choice: SuggestionVoteChoice,
        member: String,
        title: String = "severance",
        offset: TimeInterval = 0
    ) -> SharedSuggestionVote {
        SharedSuggestionVote(
            titleID: title,
            memberID: member,
            choice: choice,
            votedAt: now.addingTimeInterval(offset)
        )
    }

    private func board(_ votes: [SharedSuggestionVote]) -> SuggestionVoteBoard {
        SuggestionVoteBoard(votes: votes, currentMemberID: viewer)
    }

    // MARK: Verdicts

    func testVerdictWalksThroughTheStatesBetweenTwoPeople() {
        XCTAssertEqual(board([]).verdict(for: "severance"), .open)
        XCTAssertEqual(board([vote(.like, member: viewer)]).verdict(for: "severance"), .waitingForPartner)
        XCTAssertEqual(board([vote(.like, member: partner)]).verdict(for: "severance"), .waitingForYou)
        XCTAssertEqual(
            board([vote(.like, member: viewer), vote(.like, member: partner)]).verdict(for: "severance"),
            .match
        )
        XCTAssertEqual(
            board([vote(.like, member: viewer), vote(.pass, member: partner)]).verdict(for: "severance"),
            .passed
        )
        XCTAssertEqual(
            board([vote(.pass, member: viewer), vote(.like, member: partner)]).verdict(for: "severance"),
            .passed
        )
        XCTAssertEqual(
            board([vote(.maybe, member: viewer), vote(.like, member: partner)]).verdict(for: "severance"),
            .undecided
        )
    }

    func testVerdictIgnoresOtherTitles() {
        let votes = [vote(.like, member: viewer, title: "other"), vote(.like, member: partner, title: "other")]
        XCTAssertEqual(board(votes).verdict(for: "severance"), .open)
        XCTAssertEqual(board(votes).verdict(for: "other"), .match)
    }

    func testMatchesListNewestAgreementFirst() {
        let votes = [
            vote(.like, member: viewer, title: "a", offset: 0),
            vote(.like, member: partner, title: "a", offset: 10),
            vote(.like, member: viewer, title: "b", offset: 100),
            vote(.like, member: partner, title: "b", offset: 110),
            vote(.like, member: viewer, title: "c", offset: 200)
        ]
        XCTAssertEqual(board(votes).matchedTitleIDs, ["b", "a"])
    }

    func testAwaitingMyAnswerSkipsPartnerPassesAndMyOwnVotes() {
        let votes = [
            vote(.like, member: partner, title: "wants"),
            vote(.maybe, member: partner, title: "maybe"),
            vote(.pass, member: partner, title: "no"),
            vote(.like, member: partner, title: "answered"),
            vote(.pass, member: viewer, title: "answered")
        ]
        XCTAssertEqual(board(votes).awaitingMyAnswerTitleIDs, ["maybe", "wants"])
    }

    // MARK: Merge

    func testMergeKeepsTheLatestVotePerMemberAndTitle() {
        let remote = [vote(.like, member: viewer, offset: 0), vote(.like, member: partner, offset: 5)]
        let local = [vote(.pass, member: viewer, offset: 10)]

        let merged = SuggestionVoteReconciler.merge(remote: remote, local: local)

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first { $0.memberID == viewer }?.choice, .pass)
        XCTAssertEqual(merged.first { $0.memberID == partner }?.choice, .like)
    }

    func testMergeDoesNotLetAnOlderRemoteVoteOverwriteANewerLocalOne() {
        let remote = [vote(.pass, member: viewer, offset: 0)]
        let local = [vote(.like, member: viewer, offset: 10)]

        let merged = SuggestionVoteReconciler.merge(remote: remote, local: local)

        XCTAssertEqual(merged.map(\.choice), [.like])
    }

    func testMergeIsOrderIndependent() {
        let first = [vote(.like, member: viewer, offset: 0), vote(.maybe, member: partner, offset: 3)]
        let second = [vote(.pass, member: viewer, offset: 7), vote(.like, member: partner, offset: 2)]

        XCTAssertEqual(
            SuggestionVoteReconciler.merge(remote: first, local: second),
            SuggestionVoteReconciler.merge(remote: second, local: first)
        )
    }

    // MARK: Persistence format

    private func roundTrip(_ space: SharedSpace) throws -> SharedSpace {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SharedSpace.self, from: encoder.encode(space))
    }

    func testVotesRoundTripThroughTheSharedSpacePayload() throws {
        var space = LibrarySnapshot.sample.sharedSpace
        space.suggestionVotes = [vote(.like, member: viewer)]

        let decoded = try roundTrip(space)

        XCTAssertEqual(decoded.suggestionVotes, space.suggestionVotes)
    }

    func testOlderPayloadsWithoutVotesStillDecode() throws {
        var space = LibrarySnapshot.sample.sharedSpace
        space.suggestionVotes = nil

        let decoded = try roundTrip(space)

        XCTAssertNil(decoded.suggestionVotes)
    }

    // MARK: AppModel

    func testCastingAVoteRecordsItForTheCurrentMemberAndReplacesAnEarlierOne() throws {
        let model = AppModel(store: MemoryLibraryStore(), seed: .sample)
        let title = try XCTUnwrap(model.titles.first)

        model.castSuggestionVote(.maybe, for: title, at: now)
        model.castSuggestionVote(.like, for: title, at: now.addingTimeInterval(5))

        XCTAssertEqual(model.suggestionVoteBoard.myChoice(for: title.id), .like)
        XCTAssertEqual(model.sharedSpace.suggestionVotes?.count, 1)
    }

    func testVotedTitlesTravelWithTheSharedMetadata() throws {
        let model = AppModel(store: MemoryLibraryStore(), seed: .sample)
        let title = try XCTUnwrap(model.titles.first)
        model.sharedSpace.titleIDs = []
        model.sharedSpace.titleMetadata = []

        model.castSuggestionVote(.like, for: title)

        XCTAssertTrue(model.sharedSpace.titleMetadata?.contains { $0.id == title.id } == true)
    }

    func testAVoteOnATitleOutsideTheLibraryStillShipsItsMetadata() throws {
        let model = AppModel(store: MemoryLibraryStore(), seed: .sample)
        let searchOnly = try XCTUnwrap(model.titles.first)
        model.titles.removeAll { $0.id == searchOnly.id }
        model.sharedSpace.titleIDs = []
        model.sharedSpace.titleMetadata = []
        XCTAssertFalse(model.discoverableTitles.contains { $0.id == searchOnly.id })

        model.castSuggestionVote(.like, for: searchOnly)

        XCTAssertTrue(model.sharedSpace.titleMetadata?.contains { $0.id == searchOnly.id } == true)
    }

    func testRevokingOrLeavingForgetsTheFormerPartnersVotes() throws {
        for state in [SharedMembershipState.revoked, .left] {
            let model = AppModel(store: MemoryLibraryStore(), seed: .sample)
            let title = try XCTUnwrap(model.titles.first)
            model.castSuggestionVote(.like, for: title)

            model.setSharedMembershipState(state)

            XCTAssertNil(model.sharedSpace.suggestionVotes, "\(state) should clear votes")
        }
    }

    func testChatIsTheDefaultFrontDoor() {
        XCTAssertEqual(AppTab.launchDefault, .chat)
    }

    func testDailyCardsAreDistinctTitles() {
        let model = AppModel(store: MemoryLibraryStore(), seed: .sample)

        let cards = model.dailySuggestionCards

        XCTAssertFalse(cards.isEmpty)
        XCTAssertLessThanOrEqual(cards.count, 3)
        XCTAssertEqual(Set(cards.map(\.id)).count, cards.count)
    }

    // MARK: Pairing

    func testVotesCastBeforePairingBelongToTheCurrentMemberAfterwards() {
        let solo = [vote(.like, member: SharedSpace.localMemberID)]

        let adopted = SuggestionVoteReconciler.adoptingPlaceholder(solo, as: "real-me")

        XCTAssertEqual(adopted.map(\.memberID), ["real-me"])
        XCTAssertEqual(
            SuggestionVoteBoard(votes: adopted, currentMemberID: "real-me").myChoice(for: "severance"),
            .like
        )
    }

    func testAnAdoptedVoteLosesToALaterVoteUnderTheRealID() {
        let votes = [
            vote(.like, member: SharedSpace.localMemberID, offset: 0),
            vote(.pass, member: "real-me", offset: 10)
        ]

        let adopted = SuggestionVoteReconciler.adoptingPlaceholder(votes, as: "real-me")

        XCTAssertEqual(adopted.map(\.choice), [.pass])
    }

    func testAdoptionLeavesOtherMembersAndPlaceholderOnlySpacesAlone() {
        let partnerVote = vote(.like, member: partner)
        XCTAssertEqual(
            SuggestionVoteReconciler.adoptingPlaceholder([partnerVote], as: "real-me"),
            [partnerVote]
        )
        let solo = [vote(.like, member: SharedSpace.localMemberID)]
        XCTAssertEqual(
            SuggestionVoteReconciler.adoptingPlaceholder(solo, as: SharedSpace.localMemberID),
            solo
        )
    }

    // MARK: Daily picks

    func testDailyPicksKeepEarlierCardsAndOnlyFillOpenSlots() throws {
        let titles = Array(LibrarySnapshot.sample.titles.prefix(4))
        try XCTSkipIf(titles.count < 4, "Sample library needs four titles")
        let matches = titles.map { DiscoveryAssistantMatch(title: $0, reason: "r", score: 1) }

        let kept = DailySuggestionPicker.stable(current: [matches[1]], fresh: matches)

        XCTAssertEqual(kept.map(\.id), [matches[1].id, matches[0].id, matches[2].id])
        XCTAssertEqual(
            DailySuggestionPicker.stable(current: Array(matches.prefix(3)), fresh: [matches[3]]).map(\.id),
            matches.prefix(3).map(\.id)
        )
    }
}

final class SuggestionCardStatusTests: XCTestCase {
    func testStatusIsHiddenWithoutAPartner() {
        XCTAssertNil(
            SuggestionCardStatus.text(verdict: .match, partnerChoice: .like, partnerName: nil)
        )
    }

    func testStatusIsHiddenUntilSomeoneVotes() {
        XCTAssertNil(
            SuggestionCardStatus.text(verdict: .open, partnerChoice: nil, partnerName: "Sam")
        )
    }

    func testStatusNamesThePartnerWhileWaiting() {
        XCTAssertEqual(
            SuggestionCardStatus.text(verdict: .waitingForPartner, partnerChoice: nil, partnerName: "Sam")?.text,
            "Waiting for Sam"
        )
        XCTAssertEqual(
            SuggestionCardStatus.text(verdict: .waitingForYou, partnerChoice: .like, partnerName: "Sam")?.text,
            "Sam wants to watch this"
        )
        XCTAssertEqual(
            SuggestionCardStatus.text(verdict: .waitingForYou, partnerChoice: .maybe, partnerName: "Sam")?.text,
            "Sam might watch this"
        )
    }

    func testMatchIsTheOnlyPositiveOutcomeBothVoted() {
        XCTAssertEqual(
            SuggestionCardStatus.text(verdict: .match, partnerChoice: .like, partnerName: "Sam")?.isPositive,
            true
        )
        XCTAssertEqual(
            SuggestionCardStatus.text(verdict: .passed, partnerChoice: .pass, partnerName: "Sam")?.isPositive,
            false
        )
    }
}
