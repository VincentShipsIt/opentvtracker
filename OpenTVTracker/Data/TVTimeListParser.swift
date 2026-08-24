import CryptoKit
import Foundation

enum BoundedStableIdentifier {
    private static let hexadecimalDigits = Array("0123456789abcdef".utf8)
    private static let chunkSize = 4 * 1_024

    static func identifier(for value: String, collisionAttempt: Int = 0) -> String {
        var hasher = SHA256()
        if collisionAttempt > 0 {
            hasher.update(data: Data("collision:\(collisionAttempt)\u{0}".utf8))
        }

        var chunk: [UInt8] = []
        chunk.reserveCapacity(chunkSize)
        for byte in value.utf8 {
            chunk.append(byte)
            if chunk.count == chunkSize {
                chunk.withUnsafeBytes { hasher.update(bufferPointer: $0) }
                chunk.removeAll(keepingCapacity: true)
            }
        }
        if !chunk.isEmpty {
            chunk.withUnsafeBytes { hasher.update(bufferPointer: $0) }
        }

        let digest = hasher.finalize()
        var encoded: [UInt8] = []
        encoded.reserveCapacity("sha256-".utf8.count + SHA256.Digest.byteCount * 2)
        encoded.append(contentsOf: "sha256-".utf8)
        for byte in digest {
            encoded.append(hexadecimalDigits[Int(byte >> 4)])
            encoded.append(hexadecimalDigits[Int(byte & 0x0F)])
        }
        return String(bytes: encoded, encoding: .utf8) ?? ""
    }

    static func legacyHexIdentifier(_ identifier: Substring, matches value: String) -> Bool {
        let encoded = identifier.utf8
        var cursor = encoded.startIndex
        for byte in value.utf8 {
            guard cursor != encoded.endIndex,
                  encoded[cursor] == hexadecimalDigits[Int(byte >> 4)] else {
                return false
            }
            cursor = encoded.index(after: cursor)
            guard cursor != encoded.endIndex,
                  encoded[cursor] == hexadecimalDigits[Int(byte & 0x0F)] else {
                return false
            }
            cursor = encoded.index(after: cursor)
        }
        return cursor == encoded.endIndex
    }
}

enum TVTimeListIdentifier {
    static let maximumCollisionAttempts = 16

    static func generatedID(
        prefix: String,
        name: String,
        lists: [MediaList.ID: TVTimeList],
        identifier: (String, Int) -> String = {
            BoundedStableIdentifier.identifier(for: $0, collisionAttempt: $1)
        }
    ) throws -> MediaList.ID {
        for collisionAttempt in 0..<maximumCollisionAttempts {
            let candidate = prefix + identifier(name, collisionAttempt)
            guard let existing = lists[candidate] else { return candidate }
            if existing.name == name { return candidate }
        }
        throw TVTimeImportError.invalidArchive
    }

}

struct TVTimeListMembershipAccumulator {
    private(set) var identityIndex: [MediaList.ID: Set<String>] = [:]
    private(set) var count = 0
    let maximumCount: Int

    init(maximumCount: Int = LibraryImportLimits.maximumTVTimeListMembershipCount) {
        self.maximumCount = max(maximumCount, 0)
    }

    mutating func append(
        _ membership: TVTimeListMembership,
        listID: MediaList.ID,
        name: String,
        generatedIDPrefix: String? = nil,
        lists: inout [MediaList.ID: TVTimeList]
    ) throws {
        if let existing = lists[listID],
           existing.name != name,
           existing.generatedIDPrefix != generatedIDPrefix,
           existing.generatedIDPrefix != nil || generatedIDPrefix != nil {
            throw TVTimeImportError.invalidArchive
        }
        guard identityIndex[listID]?.contains(membership.entityIdentity) != true else {
            return
        }
        guard count < maximumCount else {
            throw LibraryImportSafetyError.tooManyTVTimeListMemberships
        }
        identityIndex[listID, default: []].insert(membership.entityIdentity)
        lists[
            listID,
            default: TVTimeList(
                id: listID,
                name: name,
                memberships: [],
                generatedIDPrefix: generatedIDPrefix
            )
        ]
            .memberships.append(membership)
        count += 1
    }
}

private struct TVTimeGDPRObjectFields {
    var type: String?
    var id: String?
    var uuid: String?
}

private struct TVTimeGDPRObjectScanner {
    typealias Index = String.UTF8View.Index

    let bytes: String.UTF8View
    let maximumFieldSize: Int
    var cursor: Index

    init(objects: String, maximumFieldSize: Int) {
        let bytes = objects.utf8
        self.bytes = bytes
        self.maximumFieldSize = max(maximumFieldSize, 0)
        cursor = bytes.startIndex
    }

    mutating func next() throws -> TVTimeGDPRObjectFields? {
        while seekToObjectStart() {
            if let fields = try parseObject() {
                return fields
            }
        }
        return nil
    }

    private mutating func seekToObjectStart() -> Bool {
        let prefix: [UInt8] = [0x6D, 0x61, 0x70, 0x5B]
        while cursor != bytes.endIndex {
            if bytes[cursor...].starts(with: prefix) {
                cursor = bytes.index(cursor, offsetBy: prefix.count)
                return true
            }
            cursor = bytes.index(after: cursor)
        }
        return false
    }

    private mutating func parseObject() throws -> TVTimeGDPRObjectFields? {
        var fields = TVTimeGDPRObjectFields()
        while cursor != bytes.endIndex {
            skipWhitespace()
            guard cursor != bytes.endIndex else { return nil }
            if bytes[cursor] == 0x5D {
                cursor = bytes.index(after: cursor)
                return fields
            }
            guard let field = try readField() else { continue }
            capture(field, in: &fields)
        }
        return nil
    }

    private mutating func skipWhitespace() {
        while cursor != bytes.endIndex, Self.isWhitespace(bytes[cursor]) {
            cursor = bytes.index(after: cursor)
        }
    }

    private mutating func readField() throws -> (key: Range<Index>, value: Range<Index>)? {
        let key = try readToken(stoppingAtColon: true)
        guard cursor != bytes.endIndex, bytes[cursor] == 0x3A else { return nil }
        cursor = bytes.index(after: cursor)
        let value = try readToken(stoppingAtColon: false)
        return value.isEmpty ? nil : (key, value)
    }

    private mutating func readToken(stoppingAtColon: Bool) throws -> Range<Index> {
        let start = cursor
        var byteCount = 0
        while cursor != bytes.endIndex {
            let byte = bytes[cursor]
            if byte == 0x5D || Self.isWhitespace(byte) || (stoppingAtColon && byte == 0x3A) {
                break
            }
            guard byteCount < maximumFieldSize else {
                throw LibraryImportSafetyError.fieldTooLarge
            }
            byteCount += 1
            cursor = bytes.index(after: cursor)
        }
        return start..<cursor
    }

    private func capture(
        _ field: (key: Range<Index>, value: Range<Index>),
        in fields: inout TVTimeGDPRObjectFields
    ) {
        let key = bytes[field.key]
        let value = bytes[field.value]
        if fields.type == nil, key.elementsEqual("type".utf8) {
            fields.type = String(bytes: value, encoding: .utf8)
        } else if fields.id == nil, key.elementsEqual("id".utf8) {
            fields.id = String(bytes: value, encoding: .utf8)
        } else if fields.uuid == nil, key.elementsEqual("uuid".utf8) {
            fields.uuid = String(bytes: value, encoding: .utf8)
        }
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
    }
}

enum TVTimeListParser {
    static func parseNative(
        _ records: [[String: String]],
        entities: inout [String: TVTimeEntity],
        lists: inout [MediaList.ID: TVTimeList],
        membershipAccumulator: inout TVTimeListMembershipAccumulator
    ) throws {
        for values in records {
            guard let name = TVTimeCSV.string(values, ["list_name"])?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !name.isEmpty,
                let sourceID = TVTimeCSV.string(values, ["tvdb_id"]) else {
                continue
            }
            let listID: MediaList.ID
            let generatedIDPrefix: String?
            if let sourceListID = TVTimeCSV.string(values, ["list_id"]) {
                listID = "tvtime:\(sourceListID)"
                generatedIDPrefix = nil
            } else {
                generatedIDPrefix = "tvtime:"
                listID = try TVTimeListIdentifier.generatedID(
                    prefix: "tvtime:",
                    name: name,
                    lists: lists
                )
            }
            let kind: MediaKind = TVTimeCSV.string(values, ["item_type"])?.lowercased() == "movie"
                ? .movie : .series
            let title = TVTimeCSV.string(values, ["name", "title"])
            let entityIdentity = identity(kind: kind, source: .tvdb, sourceID: sourceID, title: title)

            if entities[entityIdentity] == nil {
                entities[entityIdentity] = TVTimeEntity(
                    identity: entityIdentity,
                    sourceID: sourceID,
                    source: .tvdb,
                    title: title ?? "",
                    year: TVTimeCSV.year(values),
                    kind: kind
                )
            }
            try membershipAccumulator.append(
                TVTimeListMembership(
                    entityIdentity: entityIdentity,
                    order: TVTimeCSV.int(values, ["custom_order"]) ?? Int.max
                ),
                listID: listID,
                name: name,
                generatedIDPrefix: generatedIDPrefix,
                lists: &lists
            )
        }
    }

    static func parseGDPR(
        _ records: [[String: String]],
        lists: inout [MediaList.ID: TVTimeList],
        membershipAccumulator: inout TVTimeListMembershipAccumulator,
        maximumObjectFieldSize: Int = LibraryImportLimits.maximumFieldSize
    ) throws {
        for values in records {
            guard let name = TVTimeCSV.string(values, ["name"])?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !name.isEmpty,
                let objects = TVTimeCSV.string(values, ["objects"]) else {
                continue
            }
            let listID = try TVTimeListIdentifier.generatedID(
                prefix: "tvtime:gdpr:",
                name: name,
                lists: lists
            )
            var order = 0
            try forEachObject(in: objects, maximumFieldSize: maximumObjectFieldSize) { fields in
                let membershipOrder = order
                order += 1
                guard let type = fields.type else { return }
                let kind: MediaKind = type.lowercased() == "movie" ? .movie : .series
                let sourceID = kind == .movie ? fields.uuid ?? fields.id : fields.id
                guard let sourceID else { return }
                try membershipAccumulator.append(
                    TVTimeListMembership(
                        entityIdentity: identity(
                            kind: kind,
                            source: nil,
                            sourceID: sourceID,
                            title: nil
                        ),
                        order: membershipOrder
                    ),
                    listID: listID,
                    name: name,
                    generatedIDPrefix: "tvtime:gdpr:",
                    lists: &lists
                )
            }
            if lists[listID] == nil {
                lists[listID] = TVTimeList(
                    id: listID,
                    name: name,
                    memberships: [],
                    generatedIDPrefix: "tvtime:gdpr:"
                )
            }
        }
    }
}

private extension TVTimeListParser {
    static func identity(
        kind: MediaKind,
        source: ExternalCatalogSource?,
        sourceID: String,
        title: String?
    ) -> String {
        if !sourceID.isEmpty {
            let namespace = source?.rawValue ?? "source"
            return "\(kind.rawValue):\(namespace):\(sourceID)"
        }
        return "\(kind.rawValue):title:\(TVTimeCSV.normalizedTitle(title ?? ""))"
    }

    static func forEachObject(
        in objects: String,
        maximumFieldSize: Int,
        _ body: (TVTimeGDPRObjectFields) throws -> Void
    ) throws {
        var scanner = TVTimeGDPRObjectScanner(objects: objects, maximumFieldSize: maximumFieldSize)
        while let fields = try scanner.next() {
            try body(fields)
        }
    }
}
