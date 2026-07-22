import Foundation

enum TVTimeListParser {
    static func parseNative(
        _ records: [[String: String]],
        entities: inout [String: TVTimeEntity],
        lists: inout [MediaList.ID: TVTimeList]
    ) {
        for values in records {
            guard let name = TVTimeCSV.string(values, ["list_name"])?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !name.isEmpty,
                let sourceID = TVTimeCSV.string(values, ["tvdb_id"]) else {
                continue
            }
            let sourceListID = TVTimeCSV.string(values, ["list_id"]) ?? stableIdentifier(name)
            let listID = "tvtime:\(sourceListID)"
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
            append(
                TVTimeListMembership(
                    entityIdentity: entityIdentity,
                    order: TVTimeCSV.int(values, ["custom_order"]) ?? Int.max
                ),
                listID: listID,
                name: name,
                lists: &lists
            )
        }
    }

    static func parseGDPR(
        _ records: [[String: String]],
        lists: inout [MediaList.ID: TVTimeList]
    ) {
        guard let expression = try? NSRegularExpression(pattern: #"map\[(.*?)\]"#) else {
            return
        }
        for values in records {
            guard let name = TVTimeCSV.string(values, ["name"])?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !name.isEmpty,
                let objects = TVTimeCSV.string(values, ["objects"]) else {
                continue
            }
            let listID = "tvtime:gdpr:\(stableIdentifier(name))"
            let range = NSRange(objects.startIndex..<objects.endIndex, in: objects)
            for (order, match) in expression.matches(in: objects, range: range).enumerated() {
                guard let objectRange = Range(match.range(at: 1), in: objects) else {
                    continue
                }
                let object = String(objects[objectRange])
                guard let type = field("type", in: object) else { continue }
                let kind: MediaKind = type.lowercased() == "movie" ? .movie : .series
                let sourceID = kind == .movie
                    ? field("uuid", in: object) ?? field("id", in: object)
                    : field("id", in: object)
                guard let sourceID else { continue }
                append(
                    TVTimeListMembership(
                        entityIdentity: identity(kind: kind, source: nil, sourceID: sourceID, title: nil),
                        order: order
                    ),
                    listID: listID,
                    name: name,
                    lists: &lists
                )
            }
            if lists[listID] == nil {
                lists[listID] = TVTimeList(id: listID, name: name, memberships: [])
            }
        }
    }
}

private extension TVTimeListParser {
    static func append(
        _ membership: TVTimeListMembership,
        listID: MediaList.ID,
        name: String,
        lists: inout [MediaList.ID: TVTimeList]
    ) {
        var list = lists[listID] ?? TVTimeList(id: listID, name: name, memberships: [])
        if !list.memberships.contains(where: { $0.entityIdentity == membership.entityIdentity }) {
            list.memberships.append(membership)
        }
        lists[listID] = list
    }

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

    static func field(_ name: String, in object: String) -> String? {
        guard let expression = try? NSRegularExpression(
            pattern: #"(?:^|\s)"# + NSRegularExpression.escapedPattern(for: name) + #":([^\s\]]+)"#
        ) else {
            return nil
        }
        let range = NSRange(object.startIndex..<object.endIndex, in: object)
        guard let match = expression.firstMatch(in: object, range: range),
              let valueRange = Range(match.range(at: 1), in: object) else {
            return nil
        }
        return String(object[valueRange])
    }

    static func stableIdentifier(_ name: String) -> String {
        name.utf8.map { String(format: "%02x", $0) }.joined()
    }
}
