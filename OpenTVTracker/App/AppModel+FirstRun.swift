import Foundation

extension AppModel {
    func toggleFirstRunTitle(_ id: MediaTitle.ID) {
        guard let index = trackableTitleIndex(for: id) else { return }

        if titles[index].personalWatchlist == true {
            titles[index].personalWatchlist = false
            if titles[index].state == .watching {
                titles[index].state = .planned
            }
        } else {
            titles[index].personalWatchlist = true
            titles[index].state = .watching
        }

        persist()
        refreshRecommendationsSoon()
    }
}
