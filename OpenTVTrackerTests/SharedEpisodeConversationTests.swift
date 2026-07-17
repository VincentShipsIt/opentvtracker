import XCTest
@testable import OpenTVTracker

@MainActor
final class SharedEpisodeConversationTests: XCTestCase {
    func testEpisodeThreadAttachesEntriesToExactWatchEvent() throws {
        let model = makeModel()
        let title = try XCTUnwrap(model.mediaTitle(withID: "severance"))
        let season = try XCTUnwrap(title.seasons?.first)
        let episode = try XCTUnwrap(season.episodes.first)

        model.markEpisodeWatchedTogether(
            titleID: title.id,
            season: season,
            episode: episode
        )

        let event = try XCTUnwrap(
            model.conversationWatchEvent(
                titleID: title.id,
                season: season.number,
                episode: episode.number
            )
        )
        let reaction = try XCTUnwrap(
            SharedReactionAssetPolicy.asset(kind: .gif, id: "mind-blown")
        )
        model.react(to: event.id, asset: reaction)
        model.addSharedEpisodeNote("That ending.", watchEventID: event.id)

        XCTAssertEqual(model.sharedEpisodeReactions(watchEventID: event.id).first?.watchEventID, event.id)
        XCTAssertEqual(model.sharedEpisodeReactions(watchEventID: event.id).first?.episode, episode.number)
        XCTAssertEqual(model.sharedEpisodeNotes(watchEventID: event.id).first?.watchEventID, event.id)
        XCTAssertEqual(model.sharedEpisodeNotes(watchEventID: event.id).first?.text, "That ending.")
    }

    func testAlreadyWatchedEpisodeCanStartTogetherThreadWithoutDuplicateWatch() throws {
        var snapshot = Self.makeSnapshot()
        let index = try XCTUnwrap(snapshot.titles.firstIndex(where: { $0.id == "severance" }))
        snapshot.titles[index].watchedEpisodeIDs = ["s1e1"]
        let model = AppModel(store: MemoryLibraryStore(), seed: snapshot)
        let title = try XCTUnwrap(model.mediaTitle(withID: "severance"))
        let season = try XCTUnwrap(title.seasons?.first)
        let episode = try XCTUnwrap(season.episodes.first)

        model.markEpisodeWatchedTogether(titleID: title.id, season: season, episode: episode)
        model.markEpisodeWatchedTogether(titleID: title.id, season: season, episode: episode)

        XCTAssertNotNil(
            model.conversationWatchEvent(
                titleID: title.id,
                season: season.number,
                episode: episode.number
            )
        )
        XCTAssertEqual(
            model.sharedSpace.watchEvents?.filter {
                $0.kind == .watchedTogether && $0.season == 1 && $0.episode == 1
            }.count,
            model.sharedSpace.members.count
        )
    }

    func testReactionPolicyRejectsArbitraryRemoteAssets() throws {
        let model = makeModel()
        let title = try XCTUnwrap(model.mediaTitle(withID: "severance"))
        let season = try XCTUnwrap(title.seasons?.first)
        let episode = try XCTUnwrap(season.episodes.first)
        model.markEpisodeWatchedTogether(titleID: title.id, season: season, episode: episode)
        let event = try XCTUnwrap(
            model.conversationWatchEvent(titleID: title.id, season: 1, episode: 1)
        )

        model.react(
            to: event.id,
            asset: SharedReactionAsset(
                id: "https://tracker.example/reaction.gif",
                kind: .gif,
                label: "Remote",
                displayValue: "Remote",
                resourceName: nil
            )
        )

        XCTAssertTrue(model.sharedEpisodeReactions(watchEventID: event.id).isEmpty)
    }

    func testOfflineReconciliationDeduplicatesNotesAndUsesLatestReaction() {
        let event = Self.watchEvent
        let note = Self.note(id: "note", watchEventID: event.id)
        let oldReaction = Self.reaction(
            id: "reaction",
            watchEventID: event.id,
            occurredAt: Date(timeIntervalSince1970: 10)
        )
        let newReaction = Self.reaction(
            id: "reaction",
            watchEventID: event.id,
            occurredAt: Date(timeIntervalSince1970: 20),
            assetID: "wow"
        )
        var remote = Self.space(watchEvent: event)
        remote.notes = [note]
        remote.reactions = [oldReaction]
        var local = Self.space(watchEvent: event)
        local.notes = [note]
        local.reactions = [newReaction]

        let result = SharedConversationReconciler.reconcile(remote: remote, local: local)

        XCTAssertEqual(result.notes.map(\.id), ["note"])
        XCTAssertEqual(result.reactions.map(\.id), ["reaction"])
        XCTAssertEqual(result.reactions.first?.assetID, "wow")
    }

    func testDeletionWinsUntilAReactionIsRecreatedLater() {
        let event = Self.watchEvent
        let deletion = SharedConversationDeletion(
            entryID: "reaction",
            entryKind: .reaction,
            deletedAt: Date(timeIntervalSince1970: 20)
        )
        var remote = Self.space(watchEvent: event)
        remote.reactions = [
            Self.reaction(
                id: "reaction",
                watchEventID: event.id,
                occurredAt: Date(timeIntervalSince1970: 10)
            )
        ]
        remote.conversationDeletions = [deletion]

        var local = Self.space(watchEvent: event)
        local.reactions = [
            Self.reaction(
                id: "reaction",
                watchEventID: event.id,
                occurredAt: Date(timeIntervalSince1970: 30),
                assetID: "fire"
            )
        ]

        let result = SharedConversationReconciler.reconcile(remote: remote, local: local)

        XCTAssertEqual(result.reactions.first?.assetID, "fire")
        XCTAssertEqual(result.deletions, [deletion])
    }
}

extension SharedEpisodeConversationTests {
    func testNotificationPlannerOnlyUsesInvitedRemoteMembersAndRedactsContent() throws {
        let now = Date(timeIntervalSince1970: 100)
        let event = Self.watchEvent
        var space = Self.space(watchEvent: event)
        let partnerNote = SharedNote(
            id: "partner-note",
            titleID: event.titleID,
            memberID: "partner",
            text: "The villain survives.",
            createdAt: now,
            watchEventID: event.id,
            season: 1,
            episode: 1
        )
        let outsiderNote = SharedNote(
            id: "outsider-note",
            titleID: event.titleID,
            memberID: "outsider",
            text: "Spoiler",
            createdAt: now,
            watchEventID: event.id,
            season: 1,
            episode: 1
        )
        space.notes = [partnerNote, outsiderNote]

        let notifications = SharedConversationNotificationPlanner.notifications(
            for: [.note(partnerNote), .note(outsiderNote)],
            in: space,
            excluding: [],
            now: now
        )
        let notification = try XCTUnwrap(notifications.first)

        XCTAssertEqual(notifications.count, 1)
        XCTAssertEqual(notification.memberName, "Partner")
        XCTAssertFalse(notification.body.contains(partnerNote.text))
        XCTAssertTrue(notification.body.contains("after you watch"))
    }

    func testConversationCSVAndCompleteJSONIncludePrivateEntries() throws {
        var snapshot = Self.makeSnapshot()
        snapshot.sharedSpace.notes = [
            Self.note(id: "note", watchEventID: Self.watchEvent.id)
        ]
        snapshot.sharedSpace.reactions = [
            Self.reaction(
                id: "reaction",
                watchEventID: Self.watchEvent.id,
                occurredAt: Date(timeIntervalSince1970: 10)
            )
        ]
        snapshot.sharedSpace.watchEvents = [Self.watchEvent]

        let csv = try XCTUnwrap(
            String(
                data: LibraryTransferService.exportPrivateConversationsCSV(snapshot),
                encoding: .utf8
            )
        )
        let decoded = try LibraryArchiveCodec.decode(
            LibraryTransferService.exportJSON(snapshot)
        )

        XCTAssertTrue(csv.contains("reaction,reaction,\(Self.watchEvent.id)"))
        XCTAssertTrue(csv.contains("note,note,\(Self.watchEvent.id)"))
        XCTAssertEqual(decoded.sharedSpace.notes?.first?.id, "note")
        XCTAssertEqual(decoded.sharedSpace.reactions?.first?.id, "reaction")
    }

    func testSharedSpaceOwnerCanDeleteConversationWithoutDeletingWatchHistory() throws {
        let model = makeModel()
        let title = try XCTUnwrap(model.mediaTitle(withID: "severance"))
        let season = try XCTUnwrap(title.seasons?.first)
        let episode = try XCTUnwrap(season.episodes.first)
        model.markEpisodeWatchedTogether(titleID: title.id, season: season, episode: episode)
        let event = try XCTUnwrap(
            model.conversationWatchEvent(titleID: title.id, season: 1, episode: 1)
        )
        let asset = try XCTUnwrap(SharedReactionAssetPolicy.asset(kind: .emoji, id: "love"))
        model.react(to: event.id, asset: asset)
        model.addSharedEpisodeNote("Private note", watchEventID: event.id)
        let watchEventCount = model.sharedSpace.watchEvents?.count

        model.deletePrivateConversationData()

        XCTAssertEqual(model.sharedSpace.reactions, [])
        XCTAssertEqual(model.sharedSpace.notes, [])
        XCTAssertEqual(model.sharedSpace.conversationDeletions?.count, 2)
        XCTAssertEqual(model.sharedSpace.watchEvents?.count, watchEventCount)
    }

    private func makeModel() -> AppModel {
        AppModel(store: MemoryLibraryStore(), seed: Self.makeSnapshot())
    }

    private static func makeSnapshot() -> LibrarySnapshot {
        var snapshot = LibrarySnapshot.sample
        let index = snapshot.titles.firstIndex(where: { $0.id == "severance" })!
        snapshot.titles[index].seasons = [
            SeasonSummary(
                id: "season-1",
                number: 1,
                title: "Season 1",
                episodes: [
                    EpisodeSummary(
                        id: "s1e1",
                        number: 1,
                        title: "Episode 1",
                        airDate: nil,
                        runtimeMinutes: 50
                    )
                ]
            )
        ]
        snapshot.titles[index].watchedEpisodeIDs = []
        snapshot.sharedSpace.titleIDs = ["severance"]
        snapshot.sharedSpace.watchEvents = []
        snapshot.sharedSpace.reactions = []
        snapshot.sharedSpace.notes = []
        snapshot.sharedSpace.conversationDeletions = []
        snapshot.sharedSpace.isCurrentUserShareOwner = true
        return snapshot
    }

    private static let watchEvent = SharedWatchEvent(
        id: "watch-event",
        titleID: "severance",
        memberID: "you",
        kind: .watchedTogether,
        season: 1,
        episode: 1,
        occurredAt: Date(timeIntervalSince1970: 1),
        supersedesEventID: nil
    )

    private static func space(watchEvent: SharedWatchEvent) -> SharedSpace {
        SharedSpace(
            id: "space",
            name: "Our space",
            members: [
                SpaceMember(id: "you", name: "You", initials: "Y", isCurrentUser: true),
                SpaceMember(id: "partner", name: "Partner", initials: "P", isCurrentUser: false)
            ],
            titleIDs: ["severance"],
            activity: [],
            isCloudSharingEnabled: true,
            membershipState: .accepted,
            watchEvents: [watchEvent],
            reactions: [],
            notes: [],
            conversationDeletions: [],
            isCurrentUserShareOwner: true
        )
    }

    private static func reaction(
        id: String,
        watchEventID: SharedWatchEvent.ID,
        occurredAt: Date,
        assetID: String = "love"
    ) -> SharedReaction {
        SharedReaction(
            id: id,
            activityID: "activity",
            memberID: "partner",
            symbol: "❤️",
            occurredAt: occurredAt,
            watchEventID: watchEventID,
            titleID: "severance",
            season: 1,
            episode: 1,
            assetKind: .emoji,
            assetID: assetID
        )
    }

    private static func note(
        id: String,
        watchEventID: SharedWatchEvent.ID
    ) -> SharedNote {
        SharedNote(
            id: id,
            titleID: "severance",
            memberID: "partner",
            text: "Private note",
            createdAt: Date(timeIntervalSince1970: 10),
            watchEventID: watchEventID,
            season: 1,
            episode: 1
        )
    }
}
