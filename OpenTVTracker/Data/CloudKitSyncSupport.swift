import CloudKit
import Foundation
import os

enum CloudDatabaseScope: String, Codable, Sendable {
    case privateDatabase
    case sharedDatabase
}

struct CloudSyncMutation: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let recordType: String
    let recordName: String
    let zoneName: String
    let ownerName: String
    let parentRecordName: String?
    let payload: Data?
    let updatedAt: Date

    var recordID: CKRecord.ID {
        CKRecord.ID(
            recordName: recordName,
            zoneID: CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
        )
    }

    func replacing(payload: Data, updatedAt: Date) -> Self {
        Self(
            id: id,
            recordType: recordType,
            recordName: recordName,
            zoneName: zoneName,
            ownerName: ownerName,
            parentRecordName: parentRecordName,
            payload: payload,
            updatedAt: updatedAt
        )
    }
}

enum CloudRecordSystemFieldsError: Error {
    case decodeFailed
}

enum CloudKitBatchResultError: Error {
    case missingResult
}

enum CloudKitBatchResultValidator {
    static func savedZone(
        _ zoneID: CKRecordZone.ID,
        in results: [CKRecordZone.ID: Result<CKRecordZone, Error>]
    ) throws {
        guard let result = results[zoneID] else { throw CloudKitBatchResultError.missingResult }
        _ = try result.get()
    }

    static func savedRecords(
        _ recordIDs: [CKRecord.ID],
        in results: [CKRecord.ID: Result<CKRecord, Error>]
    ) throws {
        for recordID in recordIDs {
            guard let result = results[recordID] else { throw CloudKitBatchResultError.missingResult }
            _ = try result.get()
        }
    }
}

enum CloudRecordSystemFields {
    static func encode(_ record: CKRecord) throws -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        return archiver.encodedData
    }

    static func decode(_ data: Data) throws -> CKRecord {
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = true
        defer { unarchiver.finishDecoding() }
        guard let record = CKRecord(coder: unarchiver) else {
            throw CloudRecordSystemFieldsError.decodeFailed
        }
        return record
    }
}

enum CloudSyncRecordBuilder {
    static func record(
        for mutation: CloudSyncMutation,
        systemFields: Data?
    ) -> CKRecord {
        let restoredRecord = systemFields
            .flatMap { try? CloudRecordSystemFields.decode($0) }
            .flatMap { record in
                record.recordID == mutation.recordID && record.recordType == mutation.recordType
                    ? record
                    : nil
            }
        let record = restoredRecord
            ?? CKRecord(recordType: mutation.recordType, recordID: mutation.recordID)
        return populate(record, from: mutation)
    }

    @discardableResult
    static func populate(_ record: CKRecord, from mutation: CloudSyncMutation) -> CKRecord {
        if let parentRecordName = mutation.parentRecordName {
            let parentID = CKRecord.ID(recordName: parentRecordName, zoneID: mutation.recordID.zoneID)
            record.parent = CKRecord.Reference(recordID: parentID, action: .none)
        } else {
            record.parent = nil
        }
        if let payload = mutation.payload {
            record["payload"] = payload as CKRecordValue
        } else {
            record["payload"] = nil
        }
        record["updatedAt"] = mutation.updatedAt as CKRecordValue
        record["schemaVersion"] = 1 as CKRecordValue
        return record
    }
}

enum CloudSyncConflictResolver {
    static func merging(
        mutation: CloudSyncMutation,
        into serverRecord: CKRecord
    ) -> CloudSyncMutation? {
        guard mutation.recordType == "PartnerSpaceState",
              let localPayload = mutation.payload,
              let serverPayload = serverRecord["payload"] as? Data,
              let localSpace = try? CloudSyncPayloadCodec.decode(localPayload),
              let serverSpace = try? CloudSyncPayloadCodec.decode(serverPayload),
              let mergedPayload = try? CloudSyncPayloadCodec.encode(
                  LibraryBackupMerge.sharedSpace(imported: serverSpace, into: localSpace)
              ) else {
            return nil
        }
        let serverUpdatedAt = serverRecord["updatedAt"] as? Date ?? .distantPast
        return mutation.replacing(
            payload: mergedPayload,
            updatedAt: max(mutation.updatedAt, serverUpdatedAt)
        )
    }
}

enum CloudSyncPayloadCodec {
    static func encode(_ space: SharedSpace) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(space)
    }

    static func decode(_ data: Data) throws -> SharedSpace {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SharedSpace.self, from: data)
    }
}

enum CloudSyncRetryReason: String, Codable, Sendable {
    case conflict
    case missingRecord
    case zoneRecovery
}

enum CloudSyncFailurePolicy {
    static let maximumApplicationRetries = 1

    static func saveDecision(
        for error: CKError,
        scope: CloudDatabaseScope,
        applicationRetryCount: Int,
        pendingZoneRecovery: Bool = false
    ) -> CloudKitRetryDecision {
        if isEngineManaged(error.code) { return .engineManaged }
        if shouldResumePendingZoneRecovery(
            for: error,
            scope: scope,
            pendingZoneRecovery: pendingZoneRecovery
        ) {
            return pendingZoneRecoveryDecision(applicationRetryCount: applicationRetryCount)
        }
        switch error.code {
        case .serverRecordChanged where error.serverRecord != nil:
            return applicationRetryCount < maximumApplicationRetries
                ? .retryServerRecord
                : .deferUntilNextSync
        case .zoneNotFound where scope == .privateDatabase:
            return applicationRetryCount < maximumApplicationRetries
                ? .recreateZoneAndRetry
                : .deferUntilNextSync
        case .unknownItem:
            return applicationRetryCount < maximumApplicationRetries
                ? .retryWithoutSystemFields
                : .deferUntilNextSync
        default:
            return .noRetry
        }
    }

    static func retryReason(
        for error: CKError,
        scope: CloudDatabaseScope,
        pendingZoneRecovery: Bool = false
    ) -> CloudSyncRetryReason? {
        if shouldResumePendingZoneRecovery(
            for: error,
            scope: scope,
            pendingZoneRecovery: pendingZoneRecovery
        ) {
            return .zoneRecovery
        }
        return switch error.code {
        case .serverRecordChanged where error.serverRecord != nil:
            .conflict
        case .zoneNotFound where scope == .privateDatabase:
            .zoneRecovery
        case .unknownItem:
            .missingRecord
        default:
            nil
        }
    }

    static func pendingZoneRecoveryDecision(
        applicationRetryCount: Int
    ) -> CloudKitRetryDecision {
        applicationRetryCount < maximumApplicationRetries
            ? .recreateZoneAndRetry
            : .deferUntilNextSync
    }

    private static func shouldResumePendingZoneRecovery(
        for error: CKError,
        scope: CloudDatabaseScope,
        pendingZoneRecovery: Bool
    ) -> Bool {
        pendingZoneRecovery
            && scope == .privateDatabase
            && error.code == .unknownItem
    }

    static func zoneSaveDecision(for error: CKError) -> CloudKitRetryDecision {
        if isEngineManaged(error.code) { return .engineManaged }
        return .noRetry
    }

    static func deleteDecision(for error: CKError) -> CloudKitRetryDecision {
        if isEngineManaged(error.code) { return .engineManaged }
        switch error.code {
        case .unknownItem, .zoneNotFound:
            return .acknowledgeAlreadyDeleted
        default:
            return .noRetry
        }
    }

    private static func isEngineManaged(_ code: CKError.Code) -> Bool {
        switch code {
        case .accountTemporarilyUnavailable,
             .networkFailure,
             .networkUnavailable,
             .notAuthenticated,
             .operationCancelled,
             .requestRateLimited,
             .serviceUnavailable,
             .zoneBusy:
            true
        default:
            false
        }
    }
}

enum CloudKitOperation: String, Sendable {
    case acceptInvitation
    case createInvitation
    case createShare
    case fetchZone
    case saveInvitationParticipant
    case saveZone
    case syncFetchChanges
    case syncPersistSystemFields
    case syncRecordDelete
    case syncRecordSave
    case syncSendChanges
    case syncZoneDelete
    case syncZoneSave
}

enum CloudKitRetryDecision: String, Equatable, Sendable {
    case acknowledgeAlreadyDeleted
    case bootstrapZone
    case deferUntilNextSync
    case engineManaged
    case noRetry
    case recreateZoneAndRetry
    case retryServerRecord
    case retryWithoutSystemFields
}

struct CloudKitDiagnostic: Equatable, Sendable {
    let operation: CloudKitOperation
    let databaseScope: CloudDatabaseScope
    let errorCode: Int?
    let retryDecision: CloudKitRetryDecision

    var summary: String {
        let code = errorCode.map(String.init) ?? "unavailable"
        return "operation=\(operation.rawValue) databaseScope=\(databaseScope.rawValue) "
            + "ckErrorCode=\(code) retryDecision=\(retryDecision.rawValue)"
    }
}

enum CloudKitErrorInspector {
    static func contains(_ code: CKError.Code, in error: Error) -> Bool {
        allErrors(in: error).contains { $0.code == code }
    }

    static func preferredError(in error: Error) -> CKError? {
        let errors = allErrors(in: error)
        return errors.first(where: { $0.code == .quotaExceeded })
            ?? errors.first(where: { $0.code != .partialFailure })
            ?? errors.first
    }

    private static func allErrors(in error: Error) -> [CKError] {
        guard let cloudError = error as? CKError else { return [] }
        let nested = cloudError.partialErrorsByItemID?.values.flatMap(allErrors(in:)) ?? []
        return [cloudError] + nested
    }
}

enum CloudKitDiagnostics {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "dev.opentvtracker.app",
        category: "CloudKit"
    )

    @discardableResult
    static func record(
        _ error: Error,
        operation: CloudKitOperation,
        scope: CloudDatabaseScope,
        retryDecision: CloudKitRetryDecision
    ) -> CloudKitDiagnostic {
        let diagnostic = CloudKitDiagnostic(
            operation: operation,
            databaseScope: scope,
            errorCode: CloudKitErrorInspector.preferredError(in: error)?.code.rawValue,
            retryDecision: retryDecision
        )
        if retryDecision == .noRetry {
            logger.error("\(diagnostic.summary, privacy: .public)")
        } else {
            logger.info("\(diagnostic.summary, privacy: .public)")
        }
        return diagnostic
    }
}
