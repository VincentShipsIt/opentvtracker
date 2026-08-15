import CloudKit
import Foundation

struct CloudKitPartnerSharingService: PartnerSharingProviding {
    static let containerIdentifier = "iCloud.dev.opentvtracker.app"

    private let container: CKContainer

    init(container: CKContainer = CKContainer(identifier: Self.containerIdentifier)) {
        self.container = container
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
            return try await createInvitation(for: spaceID)
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

    func revoke(spaceID: SharedSpace.ID) async throws {
        let zoneID = Self.zoneID(for: spaceID)
        do {
            _ = try await container.privateCloudDatabase.modifyRecordZones(saving: [], deleting: [zoneID])
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

    private func createInvitation(for spaceID: SharedSpace.ID) async throws -> URL {
        let database = container.privateCloudDatabase
        let zoneID = Self.zoneID(for: spaceID)
        try await ensureZone(zoneID, database: database)

        let rootID = CKRecord.ID(recordName: "space-root", zoneID: zoneID)
        if let existingShare = try await Self.existingShare(rootID: rootID, database: database) {
            return try await addInvitationParticipant(
                to: existingShare,
                rootID: rootID,
                database: database
            )
        }

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
            guard let existingShare = try await existingShare(rootID: rootID, database: database) else {
                throw error
            }
            return (existingShare, true)
        }
    }

    private func addInvitationParticipant(
        to share: CKShare,
        rootID: CKRecord.ID,
        database: CKDatabase
    ) async throws -> URL {
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

    private func saveInvitationParticipant(to share: CKShare, database: CKDatabase) async throws -> URL {
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
        return url
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

    static func existingShare(rootID: CKRecord.ID, database: CKDatabase) async throws -> CKShare? {
        let results = try await database.records(for: [rootID])
        guard let result = results[rootID], let root = try? result.get(),
              let reference = root[CKRecord.SystemFieldKey.share] as? CKRecord.Reference else { return nil }
        let shareResults = try await database.records(for: [reference.recordID])
        guard let shareResult = shareResults[reference.recordID],
              let share = try? shareResult.get() as? CKShare else { return nil }
        return share
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

    static func makeInitialShare(
        spaceID: SharedSpace.ID,
        rootID: CKRecord.ID
    ) -> (root: CKRecord, share: CKShare) {
        let root = CKRecord(recordType: "PartnerSpace", recordID: rootID)
        root["spaceID"] = spaceID as CKRecordValue
        root["schemaVersion"] = 1 as CKRecordValue
        root["createdAt"] = Date.now as CKRecordValue

        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = "OpenTV partner space" as CKRecordValue
        share[CKShare.SystemFieldKey.shareType] = "dev.opentvtracker.app.partner-space" as CKRecordValue
        share.publicPermission = .none
        return (root, share)
    }
}

extension PartnerSharingError {
    static var iCloudAccountRequired: PartnerSharingError { .accountRequired }
    static var invitationUnavailable: PartnerSharingError { .shareUnavailable }
}
