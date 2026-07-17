import Foundation

extension LibraryTransferService {
    static func exportPrivateConversationsCSV(_ snapshot: LibrarySnapshot) -> Data {
        let header = [
            "entry_type", "entry_id", "watch_event_id", "title_id", "season", "episode",
            "member_id", "reaction_kind", "reaction_asset_id", "note", "occurred_at"
        ]
        let reactionRows = (snapshot.sharedSpace.reactions ?? []).map { reaction in
            let asset = SharedReactionAssetPolicy.asset(for: reaction)
            return [
                "reaction",
                reaction.id,
                reaction.watchEventID ?? "",
                reaction.titleID ?? "",
                reaction.season.map { String($0) } ?? "",
                reaction.episode.map { String($0) } ?? "",
                reaction.memberID,
                reaction.assetKind?.rawValue ?? asset?.kind.rawValue ?? "legacy",
                reaction.assetID ?? asset?.id ?? reaction.symbol,
                "",
                ISO8601DateFormatter().string(from: reaction.occurredAt)
            ]
        }
        let noteRows = (snapshot.sharedSpace.notes ?? []).map { note in
            [
                "note",
                note.id,
                note.watchEventID ?? "",
                note.titleID,
                note.season.map { String($0) } ?? "",
                note.episode.map { String($0) } ?? "",
                note.memberID,
                "",
                "",
                note.text,
                ISO8601DateFormatter().string(from: note.createdAt)
            ]
        }
        return conversationCSVData(header: header, rows: reactionRows + noteRows)
    }

    private static func conversationCSVData(header: [String], rows: [[String]]) -> Data {
        ([header] + rows)
            .map { $0.map(escapedConversationCSVField).joined(separator: ",") }
            .joined(separator: "\n")
            .appending("\n")
            .data(using: .utf8) ?? Data()
    }

    private static func escapedConversationCSVField(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else {
            return field
        }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
