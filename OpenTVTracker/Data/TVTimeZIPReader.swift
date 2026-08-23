import Foundation
import ZIPFoundation

enum TVTimeZIPReader {
    private static let maximumExpandedSize: UInt64 = 300 * 1_024 * 1_024
    private static let maximumEntrySize: UInt64 = 75 * 1_024 * 1_024

    static func recognizedFiles(in data: Data) throws -> [String: Data] {
        guard !data.isEmpty else { throw TVTimeImportError.emptyArchive }
        guard data.count <= LibraryImportLimits.maximumZIPFileSize else {
            throw TVTimeImportError.archiveTooLarge
        }

        let archive: Archive
        do {
            archive = try Archive(data: data, accessMode: .read)
        } catch {
            throw TVTimeImportError.invalidArchive
        }

        let entries = try fileEntries(in: archive)
        let recognizedEntries = try recognizedEntries(in: entries)
        try validateExpandedSize(entries)
        var files: [String: Data] = [:]
        var extractedSize: UInt64 = 0
        for entry in recognizedEntries {
            guard entry.uncompressedSize <= maximumEntrySize else {
                throw TVTimeImportError.archiveTooLarge
            }
            let contents = try extract(entry, from: archive)
            let addition = extractedSize.addingReportingOverflow(UInt64(contents.count))
            guard !addition.overflow, addition.partialValue <= maximumExpandedSize else {
                throw TVTimeImportError.archiveTooLarge
            }
            extractedSize = addition.partialValue
            files[canonicalPath(entry.path)] = contents
        }
        guard !files.isEmpty else { throw TVTimeImportError.noSupportedData }
        return files
    }

    private static func fileEntries(in archive: Archive) throws -> [Entry] {
        var entryCount = 0
        var entries: [Entry] = []
        for entry in archive {
            entryCount += 1
            guard entryCount <= LibraryImportLimits.maximumZIPEntryCount else {
                throw TVTimeImportError.tooManyArchiveEntries
            }
            if entry.type == .file {
                entries.append(entry)
            }
        }
        return entries
    }

    private static func recognizedEntries(in entries: [Entry]) throws -> [Entry] {
        var paths = Set<String>()
        var recognized: [Entry] = []
        for entry in entries where isRecognized(entry.path) {
            guard paths.insert(canonicalPath(entry.path)).inserted else {
                throw TVTimeImportError.duplicateRecognizedPath
            }
            recognized.append(entry)
        }
        return recognized
    }

    private static func validateExpandedSize(_ entries: [Entry]) throws {
        var expandedSize: UInt64 = 0
        for entry in entries {
            let addition = expandedSize.addingReportingOverflow(entry.uncompressedSize)
            guard !addition.overflow else { throw TVTimeImportError.archiveTooLarge }
            expandedSize = addition.partialValue
        }
        guard expandedSize <= maximumExpandedSize else { throw TVTimeImportError.archiveTooLarge }
    }

    private static func extract(_ entry: Entry, from archive: Archive) throws -> Data {
        var contents = Data()
        contents.reserveCapacity(Int(entry.uncompressedSize))
        do {
            _ = try archive.extract(entry) { chunk in
                guard chunk.count <= Int(maximumEntrySize) - contents.count else {
                    throw TVTimeImportError.archiveTooLarge
                }
                contents.append(chunk)
            }
            return contents
        } catch let error as TVTimeImportError {
            throw error
        } catch {
            throw TVTimeImportError.invalidArchive
        }
    }

    private static func isRecognized(_ path: String) -> Bool {
        let filename = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        return filename == "tracking-prod-records-v2.csv"
            || filename == "tracking-prod-records.csv"
            || filename == "followed_tv_show.csv"
            || filename == "tv_show_rate.csv"
            || filename == "ratings-live-votes.csv"
            || filename.contains("tvtime-series-episodes")
            || filename.contains("tvtime-movies-")
            || filename.contains("tvtime-series-")
            || filename.contains("tvtime-lists-")
            || filename == "lists-prod-lists.csv"
    }

    private static func canonicalPath(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping.lowercased()
    }
}
