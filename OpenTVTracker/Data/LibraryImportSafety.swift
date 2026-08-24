import Foundation

enum LibraryImportLimits {
    static let maximumLibraryFileSize = 25 * 1_024 * 1_024
    static let maximumZIPFileSize = 100 * 1_024 * 1_024
    static let maximumRecordCount = 250_000
    static let maximumDecodedValueCount = 1_000_000
    static let maximumCSVValueCount = 2_000_000
    static let maximumJSONSeparatorCount = 2_000_000
    static let maximumFieldSize = 1 * 1_024 * 1_024
    static let maximumTVTimeListObjectsFieldSize = 8 * 1_024 * 1_024
    static let maximumTVTimeEntityCount = 10_000
    static let maximumTVTimeCatalogRequestCount = 250
    static let maximumTVTimeListMembershipCount = maximumRecordCount
    static let maximumImportedRewatchCount = 10_000
    static let maximumImportedOrderingValue = maximumRecordCount
    static let maximumImportedProgressValue = maximumRecordCount
    static let maximumImportedRuntimeMinutes = 7 * 24 * 60
    static let maximumImportedEpochSeconds: TimeInterval = 253_402_300_799
    static let maximumCSVFieldCount = 128
    static let maximumJSONDepth = 64
    static let maximumZIPEntryCount = 1_024

    static func boundedRewatchCount(_ value: Int) -> Int {
        min(max(value, 0), maximumImportedRewatchCount)
    }

    static func boundedOrderingValue(_ value: Int) -> Int {
        min(max(value, 0), maximumImportedOrderingValue)
    }

    static func boundedProgressValue(_ value: Int) -> Int {
        min(max(value, 0), maximumImportedProgressValue)
    }

    static func boundedRuntimeMinutes(_ value: Int) -> Int {
        min(max(value, 0), maximumImportedRuntimeMinutes)
    }

    static func incrementedRewatchCount(_ value: Int) -> Int {
        let bounded = boundedRewatchCount(value)
        return bounded < maximumImportedRewatchCount ? bounded + 1 : bounded
    }

    static func nextOrderingValue(after value: Int) -> Int {
        let bounded = boundedOrderingValue(value)
        return bounded < maximumImportedOrderingValue ? bounded + 1 : bounded
    }

    static func saturatingAdd(_ lhs: Int, _ rhs: Int) -> Int {
        let result = lhs.addingReportingOverflow(rhs)
        guard result.overflow else { return result.partialValue }
        return rhs >= 0 ? Int.max : Int.min
    }
}

enum LibraryImportSafetyError: LocalizedError, Equatable {
    case fileTooLarge
    case tooManyRecords
    case fieldTooLarge
    case tooManyFields
    case tooManyValues
    case structureTooDeep
    case malformedCSV
    case tooManyTVTimeEntities
    case tooManyTVTimeListMemberships

    var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            "The selected file is too large to import safely."
        case .tooManyRecords:
            "The selected import contains more records than OpenTV can safely process."
        case .fieldTooLarge:
            "A field in the selected import is larger than OpenTV allows."
        case .tooManyFields:
            "A record in the selected import contains more fields than OpenTV allows."
        case .tooManyValues:
            "The selected import contains more values than OpenTV can safely process."
        case .structureTooDeep:
            "The selected JSON is nested more deeply than OpenTV allows."
        case .malformedCSV:
            "OpenTV could not read the structure of this CSV file."
        case .tooManyTVTimeEntities:
            "This TV Time export contains more unique titles than OpenTV can safely resolve."
        case .tooManyTVTimeListMemberships:
            "This TV Time export contains more list memberships than OpenTV can safely import."
        }
    }
}

enum LibraryImportFileReader {
    private static let chunkSize = 1_024 * 1_024

    /// Checks the logical file size before allocation, then performs a capped read so a file
    /// replacement between the resource check and the read cannot grow memory without bound.
    static func read(from url: URL) throws -> Data {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true,
                  let fileSize = values.fileSize,
                  fileSize >= 0 else {
                throw LibraryTransferError.unreadableFile
            }

            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }

            let prefix = try handle.read(upToCount: 4) ?? Data()
            let maximumSize = TVTimeImportService.isZIPArchive(prefix)
                ? LibraryImportLimits.maximumZIPFileSize
                : LibraryImportLimits.maximumLibraryFileSize
            guard fileSize <= maximumSize else {
                throw LibraryImportSafetyError.fileTooLarge
            }

            var data = Data()
            data.reserveCapacity(fileSize)
            data.append(prefix)
            while true {
                let remaining = maximumSize - data.count
                let readSize = min(chunkSize, remaining + 1)
                guard let chunk = try handle.read(upToCount: readSize), !chunk.isEmpty else {
                    break
                }
                data.append(chunk)
                guard data.count <= maximumSize else {
                    throw LibraryImportSafetyError.fileTooLarge
                }
            }
            return data
        } catch let error as LibraryImportSafetyError {
            throw error
        } catch let error as LibraryTransferError {
            throw error
        } catch {
            throw LibraryTransferError.unreadableFile
        }
    }
}

enum BoundedCSVParser {
    static func rows(
        _ csv: String,
        maximumRecordCount: Int = LibraryImportLimits.maximumRecordCount,
        maximumFieldSize: Int = LibraryImportLimits.maximumFieldSize,
        maximumValueCount: Int = LibraryImportLimits.maximumCSVValueCount,
        maximumFieldSizesByHeader: [String: Int] = [:]
    ) throws -> [[String]] {
        var result: [[String]] = []
        try forEachRow(
            in: csv,
            maximumRecordCount: maximumRecordCount,
            maximumFieldSize: maximumFieldSize,
            maximumValueCount: maximumValueCount,
            maximumFieldSizesByHeader: maximumFieldSizesByHeader
        ) { row in
            result.append(row)
        }
        return result
    }

    /// Parses and releases each logical row before continuing. Large TV Time exports can contain
    /// hundreds of thousands of rows, so retaining the complete row matrix alongside the archive
    /// model defeats the otherwise bounded file and record limits.
    static func forEachRow(
        in csv: String,
        maximumRecordCount: Int = LibraryImportLimits.maximumRecordCount,
        maximumFieldSize: Int = LibraryImportLimits.maximumFieldSize,
        maximumValueCount: Int = LibraryImportLimits.maximumCSVValueCount,
        maximumFieldSizesByHeader: [String: Int] = [:],
        _ body: ([String]) throws -> Void
    ) throws {
        var scanner = BoundedCSVScanner(
            csv: csv,
            maximumRecordCount: maximumRecordCount,
            maximumFieldSize: maximumFieldSize,
            maximumValueCount: maximumValueCount,
            maximumFieldSizesByHeader: maximumFieldSizesByHeader
        )
        try scanner.forEachRow(body)
    }
}

private struct BoundedCSVScanner {
    typealias Index = String.UTF8View.Index

    let bytes: String.UTF8View
    let maximumRecordCount: Int
    let maximumFieldSize: Int
    let maximumValueCount: Int
    let maximumFieldSizesByHeader: [String: Int]
    var row: [String] = []
    var fieldBytes: [UInt8] = []
    var valueCount = 0
    var isQuoted = false
    var index: Index
    var fieldSizeOverridesByIndex: [Int: Int] = [:]
    var completedRowCount = 0

    init(
        csv: String,
        maximumRecordCount: Int,
        maximumFieldSize: Int,
        maximumValueCount: Int,
        maximumFieldSizesByHeader: [String: Int]
    ) {
        bytes = csv.utf8
        self.maximumRecordCount = maximumRecordCount
        self.maximumFieldSize = maximumFieldSize
        self.maximumValueCount = maximumValueCount
        self.maximumFieldSizesByHeader = maximumFieldSizesByHeader
        index = bytes.startIndex
        fieldBytes.reserveCapacity(min(maximumFieldSize, 4_096))
    }

    mutating func forEachRow(_ body: ([String]) throws -> Void) throws {
        while index != bytes.endIndex {
            let next = bytes.index(after: index)
            let skipsNext = try consume(bytes[index], next: next, body)
            index = skipsNext ? bytes.index(after: next) : next
        }
        guard !isQuoted else {
            throw LibraryImportSafetyError.malformedCSV
        }
        if !fieldBytes.isEmpty || !row.isEmpty {
            try finishRow(body)
        }
    }

    private mutating func consume(
        _ byte: UInt8,
        next: Index,
        _ body: ([String]) throws -> Void
    ) throws -> Bool {
        if byte == 0x22 {
            if isQuoted, next != bytes.endIndex, bytes[next] == 0x22 {
                try appendToField(0x22)
                return true
            }
            isQuoted.toggle()
        } else if byte == 0x2C, !isQuoted {
            try finishField()
        } else if byte == 0x0A, !isQuoted {
            try finishRow(body)
        } else if byte != 0x0D || isQuoted {
            try appendToField(byte)
        }
        return false
    }

    private mutating func appendToField(_ byte: UInt8) throws {
        let fieldSizeLimit = fieldSizeOverridesByIndex[row.count] ?? maximumFieldSize
        guard fieldBytes.count < fieldSizeLimit else {
            throw LibraryImportSafetyError.fieldTooLarge
        }
        fieldBytes.append(byte)
    }

    private mutating func finishField() throws {
        guard row.count < LibraryImportLimits.maximumCSVFieldCount else {
            throw LibraryImportSafetyError.tooManyFields
        }
        valueCount += 1
        guard valueCount <= maximumValueCount else {
            throw LibraryImportSafetyError.tooManyValues
        }
        guard let field = String(bytes: fieldBytes, encoding: .utf8) else {
            throw LibraryImportSafetyError.malformedCSV
        }
        row.append(field)
        fieldBytes.removeAll(keepingCapacity: true)
    }

    private mutating func finishRow(_ body: ([String]) throws -> Void) throws {
        try finishField()
        // The first logical row is the header and is not an imported record.
        let isHeader = completedRowCount == 0
        let importedRecordCount = max(completedRowCount - 1, 0)
        guard isHeader || importedRecordCount < max(maximumRecordCount, 0) else {
            throw LibraryImportSafetyError.tooManyRecords
        }
        if isHeader, !maximumFieldSizesByHeader.isEmpty {
            fieldSizeOverridesByIndex = fieldSizeOverrides(for: row)
        }
        try body(row)
        completedRowCount += 1
        row.removeAll(keepingCapacity: true)
    }

    private func fieldSizeOverrides(for header: [String]) -> [Int: Int] {
        Dictionary(
            uniqueKeysWithValues: header.enumerated().compactMap { index, fieldName in
                let normalized = fieldName
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                    .replacingOccurrences(of: " ", with: "_")
                return maximumFieldSizesByHeader[normalized].map { (index, $0) }
            }
        )
    }
}
