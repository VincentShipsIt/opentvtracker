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
            throw PartnerSharingError.accountRequired
        case .notConfigured:
            throw PartnerSharingError.notConfigured
        }

        do {
            return try await createInvitation(for: spaceID)
        } catch {
            throw PartnerSharingError.shareUnavailable
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
            throw PartnerSharingError.acceptanceUnavailable
        }
    }

    private func createInvitation(for spaceID: SharedSpace.ID) async throws -> URL {
        let database = container.privateCloudDatabase
        let zoneID = Self.zoneID(for: spaceID)
        try await ensureZone(zoneID, database: database)

        let rootID = CKRecord.ID(recordName: "space-root", zoneID: zoneID)
        if let existingURL = try await existingShareURL(rootID: rootID, database: database) {
            return existingURL
        }

        let root = CKRecord(recordType: "PartnerSpace", recordID: rootID)
        root["spaceID"] = spaceID as CKRecordValue
        root["schemaVersion"] = 1 as CKRecordValue
        root["createdAt"] = Date.now as CKRecordValue

        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = "OpenTV partner space" as CKRecordValue
        share[CKShare.SystemFieldKey.shareType] = "dev.opentvtracker.app.partner-space" as CKRecordValue
        share.publicPermission = .none

        let result = try await database.modifyRecords(
            saving: [root, share],
            deleting: [],
            savePolicy: .ifServerRecordUnchanged,
            atomically: true
        )
        guard let shareResult = result.saveResults[share.recordID],
              let savedShare = try shareResult.get() as? CKShare,
              let url = savedShare.url else {
            throw PartnerSharingError.shareUnavailable
        }
        return url
    }

    private func ensureZone(_ zoneID: CKRecordZone.ID, database: CKDatabase) async throws {
        let results = try await database.recordZones(for: [zoneID])
        if let result = results[zoneID], (try? result.get()) != nil { return }
        _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
    }

    private func existingShareURL(rootID: CKRecord.ID, database: CKDatabase) async throws -> URL? {
        let results = try await database.records(for: [rootID])
        guard let result = results[rootID], let root = try? result.get(),
              let reference = root[CKRecord.SystemFieldKey.share] as? CKRecord.Reference else { return nil }
        let shareResults = try await database.records(for: [reference.recordID])
        guard let shareResult = shareResults[reference.recordID],
              let share = try? shareResult.get() as? CKShare else { return nil }
        return share.url
    }

    static func zoneID(for spaceID: SharedSpace.ID) -> CKRecordZone.ID {
        let safeID = spaceID
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9-]", with: "-", options: .regularExpression)
        return CKRecordZone.ID(zoneName: "partner-\(safeID)")
    }
}
