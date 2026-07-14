import Foundation

protocol LibraryPersisting: Sendable {
    func load() async throws -> LibrarySnapshot?
    func save(_ snapshot: LibrarySnapshot) async throws
}

actor FileLibraryStore: LibraryPersisting {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

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

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        decoder = JSONDecoder()
    }

    func load() async throws -> LibrarySnapshot? {
        guard fileManager.fileExists(atPath: fileURL.path()) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(LibrarySnapshot.self, from: data)
    }

    func save(_ snapshot: LibrarySnapshot) async throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
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
