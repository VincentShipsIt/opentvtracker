import Foundation

enum TVTimeCSV {
    static func rows(
        _ csv: String,
        maximumRecordCount: Int = LibraryImportLimits.maximumRecordCount,
        maximumFieldSize: Int = LibraryImportLimits.maximumFieldSize,
        maximumValueCount: Int = LibraryImportLimits.maximumCSVValueCount,
        maximumFieldSizesByHeader: [String: Int] = [:]
    ) throws -> [[String]] {
        try BoundedCSVParser.rows(
            csv,
            maximumRecordCount: maximumRecordCount,
            maximumFieldSize: maximumFieldSize,
            maximumValueCount: maximumValueCount,
            maximumFieldSizesByHeader: maximumFieldSizesByHeader
        )
    }

    static func record(header: [String], row: [String]) -> [String: String] {
        let normalizedHeader = header.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: " ", with: "_")
        }
        let padded = row + Array(repeating: "", count: max(0, normalizedHeader.count - row.count))
        return zip(normalizedHeader, padded).reduce(into: [:]) { result, pair in
            result[pair.0] = pair.1.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    static func string(_ values: [String: String], _ keys: [String]) -> String? {
        keys.lazy.compactMap { values[$0] }.first { !$0.isEmpty }
    }

    static func int(_ values: [String: String], _ keys: [String]) -> Int? {
        string(values, keys).flatMap { value in
            if let integer = Int(value) { return integer }
            guard let number = Double(value), number.isFinite else { return nil }
            return Int(number)
        }
    }

    static func double(_ values: [String: String], _ keys: [String]) -> Double? {
        string(values, keys).flatMap(Double.init)
    }

    static func bool(_ values: [String: String], _ keys: [String]) -> Bool? {
        guard let value = string(values, keys)?.lowercased() else { return nil }
        switch value {
        case "1", "true", "yes": return true
        case "0", "false", "no": return false
        default: return nil
        }
    }

    static func year(_ values: [String: String]) -> Int? {
        if let year = int(values, ["year", "release_year"]) { return year }
        return string(values, ["release_date"]).flatMap { Int($0.prefix(4)) }
    }

    static func date(_ values: [String: String], _ keys: [String]) -> Date? {
        guard let value = string(values, keys) else { return nil }
        if let epoch = epochSeconds(value) {
            return Date(timeIntervalSince1970: epoch)
        }
        let internetFormatter = ISO8601DateFormatter()
        internetFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = internetFormatter.date(from: value) { return date }
        internetFormatter.formatOptions = [.withInternetDateTime]
        if let date = internetFormatter.date(from: value) { return date }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    private static func epochSeconds(_ value: String) -> TimeInterval? {
        let digits: String
        if value.hasPrefix("watch-date-") {
            digits = String(value.dropFirst("watch-date-".count))
        } else if value.allSatisfy(\.isNumber) {
            digits = value
        } else {
            return nil
        }
        guard let raw = TimeInterval(digits) else { return nil }
        return raw > 10_000_000_000 ? raw / 1_000 : raw
    }

    static func normalizedTitle(_ title: String) -> String {
        title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
