import Foundation

struct StreamingRegion: Hashable, Identifiable, Sendable {
    let code: String

    var id: String { code }

    init?(code: String) {
        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard Self.supportedCodes.contains(normalizedCode) else { return nil }
        self.code = normalizedCode
    }

    var flag: String {
        code.unicodeScalars.reduce(into: "") { result, scalar in
            guard let regionalIndicator = UnicodeScalar(127_397 + scalar.value) else { return }
            result.unicodeScalars.append(regionalIndicator)
        }
    }

    func displayName(locale: Locale = .autoupdatingCurrent) -> String {
        locale.localizedString(forRegionCode: code) ?? code
    }

    static func deviceDefault(locale: Locale = .autoupdatingCurrent) -> StreamingRegion {
        guard let code = locale.region?.identifier,
              let region = StreamingRegion(code: code) else {
            return .malta
        }
        return region
    }

    static let malta = StreamingRegion(uncheckedCode: "MT")

    static let available: [StreamingRegion] = supportedCodes
        .map(StreamingRegion.init(uncheckedCode:))
        .sorted {
            $0.displayName().localizedStandardCompare($1.displayName()) == .orderedAscending
        }

    private static let supportedCodes: Set<String> = Set(
        Locale.Region.isoRegions
            .map { $0.identifier.uppercased() }
            .filter { code in
                code.count == 2 && code.unicodeScalars.allSatisfy { CharacterSet.uppercaseLetters.contains($0) }
            }
    )

    private init(uncheckedCode: String) {
        code = uncheckedCode
    }
}
