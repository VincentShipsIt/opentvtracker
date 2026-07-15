import Foundation

extension AppModel {
    func askDiscoveryAssistant(_ prompt: String) -> DiscoveryAssistantResponse {
        var seenIDs: Set<MediaTitle.ID> = []
        let candidates = (titles + catalogSearchResults).filter { seenIDs.insert($0.id).inserted }
        return DiscoveryAssistantEngine.respond(
            to: prompt,
            titles: candidates,
            selectedProviderIDs: selectedProviderIDs,
            tasteProfiles: sharedSpace.tasteProfiles ?? []
        )
    }
}
