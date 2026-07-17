import Foundation
import SwiftData

protocol LibraryPersisting: Sendable {
    func load() async throws -> LibrarySnapshot?
    func save(_ snapshot: LibrarySnapshot) async throws
}

struct LibraryArchiveEnvelope: Codable, Sendable {
    static let currentSchemaVersion = 5

    let schemaVersion: Int
    let exportedAt: Date
    let snapshot: LibrarySnapshot

    init(snapshot: LibrarySnapshot, exportedAt: Date = .now) {
        schemaVersion = Self.currentSchemaVersion
        self.exportedAt = exportedAt
        self.snapshot = snapshot
    }
}

enum LibraryArchiveCodec {
    static func encode(_ snapshot: LibrarySnapshot, prettyPrinted: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        }
        return try encoder.encode(LibraryArchiveEnvelope(snapshot: snapshot))
    }

    static func decode(_ data: Data) throws -> LibrarySnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let envelope = try? decoder.decode(LibraryArchiveEnvelope.self, from: data) {
            guard envelope.schemaVersion <= LibraryArchiveEnvelope.currentSchemaVersion else {
                throw LibraryArchiveError.unsupportedSchema(envelope.schemaVersion)
            }
            return envelope.snapshot
        }

        // Version 1 stored LibrarySnapshot directly without an envelope or ISO dates.
        return try JSONDecoder().decode(LibrarySnapshot.self, from: data)
    }
}

enum LibraryArchiveError: LocalizedError {
    case unsupportedSchema(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            "This backup uses schema version \(version), which this version of OpenTV cannot import."
        }
    }
}

@Model
final class StoredLibrarySnapshot {
    @Attribute(.unique) var id: String
    var schemaVersion: Int
    @Attribute(.externalStorage) var payload: Data
    var updatedAt: Date

    init(
        id: String = "primary-library",
        schemaVersion: Int,
        payload: Data,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.payload = payload
        self.updatedAt = updatedAt
    }
}

actor SwiftDataLibraryStore: LibraryPersisting {
    private let container: ModelContainer

    init(isStoredInMemoryOnly: Bool = false) throws {
        if !isStoredInMemoryOnly,
           let applicationSupportURL = FileManager.default.urls(
               for: .applicationSupportDirectory,
               in: .userDomainMask
           ).first {
            try FileManager.default.createDirectory(
                at: applicationSupportURL,
                withIntermediateDirectories: true
            )
        }
        let configuration = ModelConfiguration(
            "OpenTVLocalLibrary",
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            cloudKitDatabase: .none
        )
        container = try ModelContainer(
            for: StoredLibrarySnapshot.self,
            configurations: configuration
        )
    }

    func load() async throws -> LibrarySnapshot? {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<StoredLibrarySnapshot>(
            predicate: #Predicate { $0.id == "primary-library" }
        )
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else { return nil }
        return try LibraryArchiveCodec.decode(record.payload)
    }

    func save(_ snapshot: LibrarySnapshot) async throws {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<StoredLibrarySnapshot>(
            predicate: #Predicate { $0.id == "primary-library" }
        )
        descriptor.fetchLimit = 1
        let payload = try LibraryArchiveCodec.encode(snapshot)

        if let record = try context.fetch(descriptor).first {
            record.schemaVersion = LibraryArchiveEnvelope.currentSchemaVersion
            record.payload = payload
            record.updatedAt = .now
        } else {
            context.insert(
                StoredLibrarySnapshot(
                    schemaVersion: LibraryArchiveEnvelope.currentSchemaVersion,
                    payload: payload
                )
            )
        }

        try context.save()
    }
}

actor FileLibraryStore: LibraryPersisting {
    private let fileURL: URL
    private let fileManager: FileManager

    init(
        fileManager: FileManager = .default,
        fileName: String = "library-v1.json"
    ) {
        self.fileManager = fileManager
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        fileURL = baseURL
            .appending(path: "OpenTVTracker", directoryHint: .isDirectory)
            .appending(path: fileName, directoryHint: .notDirectory)

    }

    func load() async throws -> LibrarySnapshot? {
        guard fileManager.fileExists(atPath: fileURL.path()) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try LibraryArchiveCodec.decode(data)
    }

    func save(_ snapshot: LibrarySnapshot) async throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try LibraryArchiveCodec.encode(snapshot, prettyPrinted: true)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}

struct MigratingLibraryStore: LibraryPersisting {
    private let primary: any LibraryPersisting
    private let legacy: any LibraryPersisting

    init(primary: any LibraryPersisting, legacy: any LibraryPersisting) {
        self.primary = primary
        self.legacy = legacy
    }

    func load() async throws -> LibrarySnapshot? {
        if let snapshot = try await primary.load() {
            return snapshot
        }
        guard let legacySnapshot = try await legacy.load() else { return nil }
        try await primary.save(legacySnapshot)
        return legacySnapshot
    }

    func save(_ snapshot: LibrarySnapshot) async throws {
        try await primary.save(snapshot)
    }
}

enum LibraryStoreFactory {
    static func makeDefault() -> any LibraryPersisting {
        do {
            return MigratingLibraryStore(
                primary: try SwiftDataLibraryStore(),
                legacy: FileLibraryStore()
            )
        } catch {
            return FileLibraryStore(fileName: "library-v2.json")
        }
    }
}

actor MemoryLibraryStore: LibraryPersisting {
    private var snapshot: LibrarySnapshot?

    init(snapshot: LibrarySnapshot? = nil) {
        self.snapshot = snapshot
    }

    func load() async throws -> LibrarySnapshot? {
        snapshot
    }

    func save(_ snapshot: LibrarySnapshot) async throws {
        self.snapshot = snapshot
    }
}
