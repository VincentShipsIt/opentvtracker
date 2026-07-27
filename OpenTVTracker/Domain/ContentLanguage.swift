import Foundation

struct ContentLanguage: Hashable, Identifiable, Sendable {
    let code: String

    var id: String { code }

    init?(code: String) {
        let normalizedCode = code
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-", maxSplits: 1)
            .first
            .map(String.init)?
            .lowercased()

        guard let normalizedCode,
              Self.supportedCodes.contains(normalizedCode) else {
            return nil
        }
        self.code = normalizedCode
    }

    func displayName(locale: Locale = .autoupdatingCurrent) -> String {
        locale.localizedString(forLanguageCode: code) ?? code.uppercased()
    }

    func catalogName() -> String {
        Locale(identifier: "en").localizedString(forLanguageCode: code) ?? code
    }

    static func deviceDefault(locale: Locale = .autoupdatingCurrent) -> ContentLanguage {
        guard let code = locale.language.languageCode?.identifier,
              let language = ContentLanguage(code: code) else {
            return .english
        }
        return language
    }

    static let english = ContentLanguage(uncheckedCode: "en")

    static let available: [ContentLanguage] = supportedCodes
        .map(ContentLanguage.init(uncheckedCode:))
        .sorted {
            $0.displayName().localizedStandardCompare($1.displayName()) == .orderedAscending
        }

    private static let supportedCodes: Set<String> = Set(
        Locale.LanguageCode.isoLanguageCodes
            .map { $0.identifier.lowercased() }
            .filter { code in
                (2...3).contains(code.count)
                    && code.unicodeScalars.allSatisfy {
                        CharacterSet.lowercaseLetters.contains($0)
                    }
                    && code != "und"
            }
    )

    private init(uncheckedCode: String) {
        code = uncheckedCode
    }
}
