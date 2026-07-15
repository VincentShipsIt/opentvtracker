import Foundation
import ZIPFoundation

enum TVTimeZIPReader {
    private static let maximumCompressedSize = 100 * 1_024 * 1_024
    private static let maximumExpandedSize: UInt64 = 300 * 1_024 * 1_024
    private static let maximumEntrySize: UInt64 = 75 * 1_024 * 1_024

    static func recognizedFiles(in data: Data) throws -> [String: Data] {
        guard !data.isEmpty else { throw TVTimeImportError.emptyArchive }
        guard data.count <= maximumCompressedSize else { throw TVTimeImportError.archiveTooLarge }

        let archive: Archive
        do {
            archive = try Archive(data: data, accessMode: .read)
        } catch {
            throw TVTimeImportError.invalidArchive
        }

        let entries = archive.filter { $0.type == .file }
        try validateExpandedSize(entries)
        var files: [String: Data] = [:]
        for entry in entries where isRecognized(entry.path) {
            guard entry.uncompressedSize <= maximumEntrySize else {
                throw TVTimeImportError.archiveTooLarge
            }
            files[entry.path.lowercased()] = try extract(entry, from: archive)
        }
        guard !files.isEmpty else { throw TVTimeImportError.noSupportedData }
        return files
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
                contents.append(chunk)
            }
            return contents
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
    }
}
