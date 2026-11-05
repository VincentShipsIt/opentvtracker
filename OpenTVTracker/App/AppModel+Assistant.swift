import Foundation

extension AppModel {
    func askDiscoveryAssistant(_ prompt: String) -> DiscoveryAssistantResponse {
        var seenIDs: Set<MediaTitle.ID> = []
        let candidates = (discoverableTitles + catalogSearchResults)
            .filter { seenIDs.insert($0.id).inserted }
        return DiscoveryAssistantEngine.respond(
            to: prompt,
            titles: candidates,
            selectedProviderIDs: selectedProviderIDs,
            tasteProfiles: sharedSpace.tasteProfiles ?? []
        )
    }
}

struct DiscoveryConversationTurn: Equatable, Identifiable, Sendable {
    let id: Int
    let prompt: String
    let response: DiscoveryAssistantResponse
}

/// A multi-turn chat over `DiscoveryAssistantEngine`. Each message refines the running
/// intent, and titles already suggested are not offered again.
struct DiscoveryConversation: Equatable, Sendable {
    private(set) var turns: [DiscoveryConversationTurn] = []
    private var intent: DiscoveryAssistantIntent?

    var shownTitleIDs: Set<MediaTitle.ID> {
        Set(turns.flatMap { $0.response.matches.map(\.title.id) })
    }

    @discardableResult
    mutating func ask(
        _ prompt: String,
        titles: [MediaTitle],
        selectedProviderIDs: Set<StreamingProvider.ID>,
        tasteProfiles: [MemberTasteProfile],
        limit: Int = 3
    ) -> DiscoveryConversationTurn {
        let followUp = DiscoveryAssistantEngine.parse(prompt)
        let merged = intent.map { $0.refined(by: followUp) } ?? followUp
        let response = DiscoveryAssistantEngine.respond(
            to: prompt,
            intent: merged,
            excludingTitleIDs: shownTitleIDs,
            context: DiscoveryAssistantContext(
                titles: titles,
                selectedProviderIDs: selectedProviderIDs,
                tasteProfiles: tasteProfiles
            ),
            limit: limit
        )
        let turn = DiscoveryConversationTurn(id: turns.count, prompt: prompt, response: response)
        intent = merged
        turns.append(turn)
        return turn
    }

    mutating func reset() {
        turns = []
        intent = nil
    }
}
