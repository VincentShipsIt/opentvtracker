import CloudKit
import Foundation

struct CloudKitPartnerSharingService: PartnerSharingProviding {
    static let containerIdentifier = "iCloud.dev.opentvtracker.app"

    private let container: CKContainer
    private let invitationStore: PartnerInvitationLinkStore

    init(
        container: CKContainer = CKContainer(identifier: Self.containerIdentifier),
        invitationStore: PartnerInvitationLinkStore = PartnerInvitationLinkStore()
    ) {
        self.container = container
        self.invitationStore = invitationStore
    }

    func availability() async -> PartnerSharingAvailability {
        do {
            switch try await container.accountStatus() {
            case .available: return .available
            case .noAccount, .restricted, .couldNotDetermine, .temporarilyUnavailable:
                return .iCloudAccountRequired
            @unknown default: return .iCloudAccountRequired
            }
        } catch {
            return .notConfigured
        }
    }

    func inviteURL(for spaceID: SharedSpace.ID) async throws -> URL {
        switch await availability() {
        case .available:
            break
        case .iCloudAccountRequired:
            throw PartnerSharingError.iCloudAccountRequired
        case .notConfigured:
            throw PartnerSharingError.notConfigured
        }

        do {
            let link = try await createInvitation(for: spaceID)
            invitationStore.append(link, spaceID: spaceID)
            return link.url
        } catch {
            CloudKitDiagnostics.record(
                error,
                operation: .createInvitation,
                scope: .privateDatabase,
                retryDecision: .noRetry
            )
            throw Self.invitationError(from: error)
        }
    }

    func invitationLinks(for spaceID: SharedSpace.ID) async throws -> [PartnerInvitationLink] {
        let stored = invitationStore.load(spaceID: spaceID)
        do {
            let database = container.privateCloudDatabase
            let rootID = CKRecord.ID(recordName: "space-root", zoneID: Self.zoneID(for: spaceID))
            guard let share = try await Self.existingShare(rootID: rootID, database: database) else {
                return stored
            }
            let merged = PartnerInvitationLinkStore.merging(
                stored: stored,
                remote: Self.pendingLinks(from: share)
            )
            invitationStore.replaceAll(merged, spaceID: spaceID)
            return merged
        } catch {
            return stored
        }
    }

    func revoke(spaceID: SharedSpace.ID) async throws {
        let zoneID = Self.zoneID(for: spaceID)
        do {
            _ = try await container.privateCloudDatabase.modifyRecordZones(saving: [], deleting: [zoneID])
            invitationStore.removeAll(spaceID: spaceID)
        } catch {
            throw PartnerSharingError.revokeUnavailable
        }
    }

    func leave(space: SharedSpace) async throws {
        let fallbackZoneID = Self.zoneID(for: space.id)
        let zoneID = CKRecordZone.ID(
            zoneName: space.cloudZoneName ?? fallbackZoneID.zoneName,
            ownerName: space.cloudOwnerName ?? fallbackZoneID.ownerName
        )
        do {
            _ = try await container.sharedCloudDatabase.modifyRecordZones(saving: [], deleting: [zoneID])
        } catch {
            throw PartnerSharingError.leaveUnavailable
        }
    }

    func accept(metadata: CKShare.Metadata) async throws {
        do {
            let results = try await container.accept([metadata])
            guard let result = results[metadata] else {
                throw PartnerSharingError.acceptanceUnavailable
            }
            _ = try result.get()
        } catch {
            CloudKitDiagnostics.record(
                error,
                operation: .acceptInvitation,
                scope: .sharedDatabase,
                retryDecision: .noRetry
            )
            throw PartnerSharingError.acceptanceUnavailable
        }
    }

    private func createInvitation(for spaceID: SharedSpace.ID) async throws -> PartnerInvitationLink {
        let database = container.privateCloudDatabase
        let zoneID = Self.zoneID(for: spaceID)
        try await ensureZone(zoneID, database: database)

        let rootID = CKRecord.ID(recordName: "space-root", zoneID: zoneID)
        let existingRoot = try await Self.fetchRoot(rootID: rootID, database: database)
        let existingShare = if let existingRoot {
            try await Self.existingShare(root: existingRoot, database: database)
        } else {
            Optional<CKShare>.none
        }

        switch PartnerShareBootstrap.action(hasRoot: existingRoot != nil, hasShare: existingShare != nil) {
        case .reuseExistingShare:
            guard let existingShare else {
                throw PartnerSharingError.invitationUnavailable
            }
            return try await addInvitationParticipant(
                to: existingShare,
                rootID: rootID,
                database: database
            )
        case .attachShareToExistingRoot:
            guard let existingRoot else {
                throw PartnerSharingError.invitationUnavailable
            }
            let savedShare = try await Self.saveShareOnExistingRoot(
                existingRoot,
                rootID: rootID,
                database: database
            )
            return try await addInvitationParticipant(
                to: savedShare,
                rootID: rootID,
                database: database
            )
        case .createInitialShare:
            let (root, share) = Self.makeInitialShare(spaceID: spaceID, rootID: rootID)
            let savedShare = try await Self.saveInitialShare(
                root: root,
                share: share,
                rootID: rootID,
                database: database
            ).share
            return try await addInvitationParticipant(
                to: savedShare,
                rootID: rootID,
                database: database
            )
        }
    }

    static func saveInitialShare(
        root: CKRecord,
        share: CKShare,
        rootID: CKRecord.ID,
        database: CKDatabase
    ) async throws -> (share: CKShare, reusedExistingShare: Bool) {
        do {
            let result = try await database.modifyRecords(
                saving: [root, share],
                deleting: [],
                savePolicy: .ifServerRecordUnchanged,
                atomically: true
            )
            try CloudKitBatchResultValidator.savedRecords(
                [root.recordID, share.recordID],
                in: result.saveResults
            )
            guard let shareResult = result.saveResults[share.recordID],
                  let share = try shareResult.get() as? CKShare else {
                throw PartnerSharingError.invitationUnavailable
            }
            return (share, false)
        } catch {
            guard Self.isServerRecordChanged(error) else {
                throw error
            }
            CloudKitDiagnostics.record(
                error,
                operation: .createShare,
                scope: .privateDatabase,
                retryDecision: .retryServerRecord
            )
            if let existingShare = try await existingShare(rootID: rootID, database: database) {
                return (existingShare, true)
            }
            guard let existingRoot = try await fetchRoot(rootID: rootID, database: database) else {
                throw error
            }
            let attachedShare = try await saveShareOnExistingRoot(
                existingRoot,
                rootID: rootID,
                database: database
            )
            return (attachedShare, false)
        }
    }

    static func saveShareOnExistingRoot(
        _ root: CKRecord,
        rootID: CKRecord.ID,
        database: CKDatabase
    ) async throws -> CKShare {
        let share = makeShare(on: root)
        do {
            let result = try await database.modifyRecords(
                saving: [root, share],
                deleting: [],
                savePolicy: .ifServerRecordUnchanged,
                atomically: true
            )
            try CloudKitBatchResultValidator.savedRecords(
                [root.recordID, share.recordID],
                in: result.saveResults
            )
            guard let shareResult = result.saveResults[share.recordID],
                  let savedShare = try shareResult.get() as? CKShare else {
                throw PartnerSharingError.invitationUnavailable
            }
            return savedShare
        } catch {
            guard isServerRecordChanged(error),
                  let latestShare = try await existingShare(rootID: rootID, database: database) else {
                throw error
            }
            return latestShare
        }
    }

    private func addInvitationParticipant(
        to share: CKShare,
        rootID: CKRecord.ID,
        database: CKDatabase
    ) async throws -> PartnerInvitationLink {
        do {
            return try await saveInvitationParticipant(to: share, database: database)
        } catch {
            guard Self.isServerRecordChanged(error) else {
                throw error
            }
            CloudKitDiagnostics.record(
                error,
                operation: .saveInvitationParticipant,
                scope: .privateDatabase,
                retryDecision: .retryServerRecord
            )
            guard let latestShare = try await Self.existingShare(rootID: rootID, database: database) else {
                throw error
            }
            return try await saveInvitationParticipant(to: latestShare, database: database)
        }
    }

    private func saveInvitationParticipant(
        to share: CKShare,
        database: CKDatabase
    ) async throws -> PartnerInvitationLink {
        guard share.publicPermission == .none else {
            throw PartnerSharingError.invitationUnavailable
        }
        let participant = Self.makePrivateInvitationParticipant()
        share.addParticipant(participant)
        let result = try await database.modifyRecords(
            saving: [share],
            deleting: [],
            savePolicy: .ifServerRecordUnchanged,
            atomically: true
        )
        guard let shareResult = result.saveResults[share.recordID],
              let savedShare = try shareResult.get() as? CKShare,
              let url = savedShare.oneTimeURL(for: participant.participantID) else {
            throw PartnerSharingError.invitationUnavailable
        }
        return PartnerInvitationLink(url: url, createdAt: Date.now)
    }

    private func ensureZone(_ zoneID: CKRecordZone.ID, database: CKDatabase) async throws {
        let results = try await database.recordZones(for: [zoneID])
        guard let result = results[zoneID] else {
            throw PartnerSharingError.invitationUnavailable
        }
        do {
            _ = try result.get()
            return
        } catch {
            guard Self.zoneBootstrapDecision(for: error) == .bootstrapZone else {
                CloudKitDiagnostics.record(
                    error,
                    operation: .fetchZone,
                    scope: .privateDatabase,
                    retryDecision: .noRetry
                )
                throw error
            }
            CloudKitDiagnostics.record(
                error,
                operation: .fetchZone,
                scope: .privateDatabase,
                retryDecision: .bootstrapZone
            )
        }

        do {
            let result = try await database.modifyRecordZones(
                saving: [CKRecordZone(zoneID: zoneID)],
                deleting: []
            )
            try CloudKitBatchResultValidator.savedZone(zoneID, in: result.saveResults)
        } catch {
            CloudKitDiagnostics.record(
                error,
                operation: .saveZone,
                scope: .privateDatabase,
                retryDecision: .noRetry
            )
            throw error
        }
    }

    static func fetchRoot(rootID: CKRecord.ID, database: CKDatabase) async throws -> CKRecord? {
        let results = try await database.records(for: [rootID])
        guard let result = results[rootID] else { return nil }
        do {
            return try result.get()
        } catch {
            if CloudKitErrorInspector.contains(.unknownItem, in: error) {
                return nil
            }
            throw error
        }
    }

    static func existingShare(root: CKRecord, database: CKDatabase) async throws -> CKShare? {
        // System fields are not exposed through CKRecord's subscript. After
        // CKShare(rootRecord:) or a server fetch, only `root.share` is populated.
        guard let reference = shareReference(on: root) else {
            return nil
        }
        let shareResults = try await database.records(for: [reference.recordID])
        guard let shareResult = shareResults[reference.recordID] else { return nil }
        do {
            return try shareResult.get() as? CKShare
        } catch {
            if CloudKitErrorInspector.contains(.unknownItem, in: error) {
                return nil
            }
            throw error
        }
    }

    static func existingShare(rootID: CKRecord.ID, database: CKDatabase) async throws -> CKShare? {
        guard let root = try await fetchRoot(rootID: rootID, database: database) else {
            return nil
        }
        return try await existingShare(root: root, database: database)
    }

    static func pendingLinks(from share: CKShare) -> [PartnerInvitationLink] {
        share.participants.compactMap { participant in
            guard participant.acceptanceStatus == .pending,
                  participant.userIdentity.lookupInfo == nil,
                  let url = share.oneTimeURL(for: participant.participantID) else {
                return nil
            }
            return PartnerInvitationLink(url: url, createdAt: Date.now)
        }
    }
}

extension CloudKitPartnerSharingService {
    static func makePrivateInvitationParticipant() -> CKShare.Participant {
        let participant = CKShare.Participant.oneTimeURLParticipant()
        participant.permission = .readWrite
        return participant
    }

    static func isServerRecordChanged(_ error: Error) -> Bool {
        CloudKitErrorInspector.contains(.serverRecordChanged, in: error)
    }

    static func zoneBootstrapDecision(for error: Error) -> CloudKitRetryDecision {
        CloudKitErrorInspector.contains(.zoneNotFound, in: error) ? .bootstrapZone : .noRetry
    }

    static func zoneID(for spaceID: SharedSpace.ID) -> CKRecordZone.ID {
        let safeID = spaceID
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9-]", with: "-", options: .regularExpression)
        return CKRecordZone.ID(zoneName: "partner-\(safeID)")
    }

    static func invitationError(from error: Error) -> PartnerSharingError {
        CloudKitErrorInspector.contains(.quotaExceeded, in: error)
            ? .iCloudStorageFull
            : .shareUnavailable
    }

    static func shareReference(on root: CKRecord) -> CKRecord.Reference? {
        root.share
    }

    static func makeShare(on root: CKRecord) -> CKShare {
        let share: CKShare
        if let shareID = shareReference(on: root)?.recordID {
            share = CKShare(rootRecord: root, shareID: shareID)
        } else {
            share = CKShare(rootRecord: root)
        }
        share[CKShare.SystemFieldKey.title] = "OpenTV partner space" as CKRecordValue
        share[CKShare.SystemFieldKey.shareType] = "dev.opentvtracker.app.partner-space" as CKRecordValue
        share.publicPermission = .none
        return share
    }

    static func makeInitialShare(
        spaceID: SharedSpace.ID,
        rootID: CKRecord.ID
    ) -> (root: CKRecord, share: CKShare) {
        let root = CKRecord(recordType: "PartnerSpace", recordID: rootID)
        root["spaceID"] = spaceID as CKRecordValue
        root["schemaVersion"] = 1 as CKRecordValue
        root["createdAt"] = Date.now as CKRecordValue
        return (root, makeShare(on: root))
    }
}

extension PartnerSharingError {
    static var iCloudAccountRequired: PartnerSharingError { .accountRequired }
    static var invitationUnavailable: PartnerSharingError { .shareUnavailable }
}

enum PartnerShareBootstrapAction: Equatable, Sendable {
    case reuseExistingShare
    case attachShareToExistingRoot
    case createInitialShare
}

enum PartnerShareBootstrap {
    static func action(hasRoot: Bool, hasShare: Bool) -> PartnerShareBootstrapAction {
        switch (hasRoot, hasShare) {
        case (true, true): .reuseExistingShare
        case (true, false): .attachShareToExistingRoot
        case (false, _): .createInitialShare
        }
    }
}

struct PartnerInvitationLinkStore: @unchecked Sendable {
    static let maximumStoredLinks = 20

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(spaceID: SharedSpace.ID) -> [PartnerInvitationLink] {
        guard let data = defaults.data(forKey: Self.key(for: spaceID)),
              let links = try? JSONDecoder().decode([PartnerInvitationLink].self, from: data) else {
            return []
        }
        return links
    }

    func append(_ link: PartnerInvitationLink, spaceID: SharedSpace.ID) {
        var links = load(spaceID: spaceID)
        links.removeAll { $0.url == link.url }
        links.insert(link, at: 0)
        replaceAll(Array(links.prefix(Self.maximumStoredLinks)), spaceID: spaceID)
    }

    func replaceAll(_ links: [PartnerInvitationLink], spaceID: SharedSpace.ID) {
        defaults.set(try? JSONEncoder().encode(links), forKey: Self.key(for: spaceID))
    }

    func removeAll(spaceID: SharedSpace.ID) {
        defaults.removeObject(forKey: Self.key(for: spaceID))
    }

    static func merging(
        stored: [PartnerInvitationLink],
        remote: [PartnerInvitationLink]
    ) -> [PartnerInvitationLink] {
        var byURL = Dictionary(uniqueKeysWithValues: stored.map { ($0.url, $0) })
        for link in remote where byURL[link.url] == nil {
            byURL[link.url] = link
        }
        return byURL.values.sorted { $0.createdAt > $1.createdAt }
    }

    private static func key(for spaceID: SharedSpace.ID) -> String {
        "opentv.partner.invitation-links.\(spaceID)"
    }
}
