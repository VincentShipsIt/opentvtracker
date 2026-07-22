import Foundation

extension AppModel {
    var partnerSharedLists: [SharedMediaList] {
        let currentMemberID = sharedSpace.members.first(where: \.isCurrentUser)?.id ?? "local-user"
        return (sharedSpace.sharedLists ?? [])
            .filter { !$0.isDeleted && $0.ownerMemberID != currentMemberID }
            .sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    @discardableResult
    func createList(named name: String) -> MediaList.ID? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isAvailableListName(trimmedName) else { return nil }
        let list = MediaList(
            id: UUID().uuidString.lowercased(),
            name: trimmedName,
            titleIDs: [],
            updatedAt: .now
        )
        lists.append(list)
        persist()
        return list.id
    }

    @discardableResult
    func renameList(_ id: MediaList.ID, to name: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = lists.firstIndex(where: { $0.id == id }),
              isAvailableListName(trimmedName, excluding: id) else {
            return false
        }
        lists[index].name = trimmedName
        lists[index].updatedAt = .now
        updateSharedListCopyIfNeeded(lists[index])
        persist()
        syncSharedStateSoon()
        return true
    }

    func deleteList(_ id: MediaList.ID) {
        guard let index = lists.firstIndex(where: { $0.id == id }) else { return }
        lists.remove(at: index)
        markSharedListDeleted(id)
        persist()
        syncSharedStateSoon()
    }

    func moveLists(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        guard moveElements(in: &lists, fromOffsets: offsets, toOffset: destination) else { return }
        persist()
    }

    func titles(inList id: MediaList.ID) -> [MediaTitle] {
        guard let list = lists.first(where: { $0.id == id }) else { return [] }
        let titlesByID = Dictionary(uniqueKeysWithValues: titles.map { ($0.id, $0) })
        return list.titleIDs.compactMap { titlesByID[$0] }
    }

    func titles(inSharedList id: SharedMediaList.ID) -> [MediaTitle] {
        guard let list = sharedList(withID: id) else { return [] }
        let titlesByID = Dictionary(uniqueKeysWithValues: titles.map { ($0.id, $0) })
        return list.titleIDs.compactMap { titlesByID[$0] }
    }

    func isTitle(_ titleID: MediaTitle.ID, inList listID: MediaList.ID) -> Bool {
        lists.first(where: { $0.id == listID })?.titleIDs.contains(titleID) == true
    }

    func toggleTitle(_ titleID: MediaTitle.ID, inList listID: MediaList.ID) {
        if isTitle(titleID, inList: listID) {
            removeTitle(titleID, fromList: listID)
        } else {
            addTitle(titleID, toList: listID)
        }
    }

    func addTitle(_ titleID: MediaTitle.ID, toList listID: MediaList.ID) {
        guard trackableTitleIndex(for: titleID) != nil,
              let listIndex = lists.firstIndex(where: { $0.id == listID }),
              !lists[listIndex].titleIDs.contains(titleID) else {
            return
        }
        lists[listIndex].titleIDs.append(titleID)
        lists[listIndex].updatedAt = .now
        updateSharedListCopyIfNeeded(lists[listIndex])
        persist()
        syncSharedStateSoon()
    }

    func removeTitle(_ titleID: MediaTitle.ID, fromList listID: MediaList.ID) {
        guard let listIndex = lists.firstIndex(where: { $0.id == listID }),
              let titleIndex = lists[listIndex].titleIDs.firstIndex(of: titleID) else {
            return
        }
        lists[listIndex].titleIDs.remove(at: titleIndex)
        lists[listIndex].updatedAt = .now
        updateSharedListCopyIfNeeded(lists[listIndex])
        persist()
        syncSharedStateSoon()
    }

    func removeTitles(at offsets: IndexSet, fromList listID: MediaList.ID) {
        guard let listIndex = lists.firstIndex(where: { $0.id == listID }) else { return }
        let visibleTitleIDs = titles(inList: listID).map(\.id)
        let removedIDs = Set(offsets.compactMap { visibleTitleIDs.indices.contains($0) ? visibleTitleIDs[$0] : nil })
        guard !removedIDs.isEmpty else { return }
        lists[listIndex].titleIDs.removeAll { removedIDs.contains($0) }
        lists[listIndex].updatedAt = .now
        updateSharedListCopyIfNeeded(lists[listIndex])
        persist()
        syncSharedStateSoon()
    }

    func moveTitles(inList listID: MediaList.ID, fromOffsets offsets: IndexSet, toOffset destination: Int) {
        guard let index = lists.firstIndex(where: { $0.id == listID }) else { return }
        let availableTitleIDs = Set(titles.map(\.id))
        let visibleIndices = lists[index].titleIDs.indices.filter {
            availableTitleIDs.contains(lists[index].titleIDs[$0])
        }
        var visibleTitleIDs = visibleIndices.map { lists[index].titleIDs[$0] }
        guard moveElements(in: &visibleTitleIDs, fromOffsets: offsets, toOffset: destination) else {
            return
        }
        for (rawIndex, titleID) in zip(visibleIndices, visibleTitleIDs) {
            lists[index].titleIDs[rawIndex] = titleID
        }
        lists[index].updatedAt = .now
        updateSharedListCopyIfNeeded(lists[index])
        persist()
        syncSharedStateSoon()
    }

    func shareListWithPartner(_ id: MediaList.ID) {
        guard let list = lists.first(where: { $0.id == id }) else { return }
        let ownerID = sharedSpace.members.first(where: \.isCurrentUser)?.id ?? "local-user"
        let sharedList = SharedMediaList(
            id: list.id,
            name: list.name,
            titleIDs: list.titleIDs,
            ownerMemberID: ownerID,
            updatedAt: .now
        )
        upsertSharedList(sharedList)
        prepareSharedTitleMetadataForSync()
        persist()
        syncSharedStateSoon()
    }

    func stopSharingList(_ id: MediaList.ID) {
        markSharedListDeleted(id)
        persist()
        syncSharedStateSoon()
    }

    func isListShared(_ id: MediaList.ID) -> Bool {
        sharedList(withID: id)?.isDeleted == false
    }

    func isTitleSharedViaList(_ id: MediaTitle.ID) -> Bool {
        (sharedSpace.sharedLists ?? []).contains { !$0.isDeleted && $0.titleIDs.contains(id) }
    }

    func sharedList(withID id: SharedMediaList.ID) -> SharedMediaList? {
        (sharedSpace.sharedLists ?? []).first { $0.id == id && !$0.isDeleted }
    }
}

private extension AppModel {
    func isAvailableListName(_ name: String, excluding excludedID: MediaList.ID? = nil) -> Bool {
        guard !name.isEmpty else { return false }
        return !lists.contains {
            $0.id != excludedID
                && $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    func updateSharedListCopyIfNeeded(_ list: MediaList) {
        guard let existing = sharedList(withID: list.id) else { return }
        upsertSharedList(
            SharedMediaList(
                id: list.id,
                name: list.name,
                titleIDs: list.titleIDs,
                ownerMemberID: existing.ownerMemberID,
                updatedAt: list.updatedAt
            )
        )
        prepareSharedTitleMetadataForSync()
    }

    func markSharedListDeleted(_ id: MediaList.ID) {
        guard let index = sharedSpace.sharedLists?.firstIndex(where: { $0.id == id }),
              sharedSpace.sharedLists?[index].isDeleted == false else {
            return
        }
        let timestamp = Date.now
        sharedSpace.sharedLists?[index].name = ""
        sharedSpace.sharedLists?[index].titleIDs = []
        sharedSpace.sharedLists?[index].updatedAt = timestamp
        sharedSpace.sharedLists?[index].deletedAt = timestamp
        prepareSharedTitleMetadataForSync()
    }

    func upsertSharedList(_ list: SharedMediaList) {
        var sharedLists = sharedSpace.sharedLists ?? []
        if let index = sharedLists.firstIndex(where: { $0.id == list.id }) {
            sharedLists[index] = list
        } else {
            sharedLists.append(list)
        }
        sharedSpace.sharedLists = sharedLists
    }

    func moveElements<Value>(
        in values: inout [Value],
        fromOffsets offsets: IndexSet,
        toOffset destination: Int
    ) -> Bool {
        let validOffsets = offsets.filter { values.indices.contains($0) }.sorted()
        guard !validOffsets.isEmpty, (0...values.count).contains(destination) else { return false }
        let moving = validOffsets.map { values[$0] }
        for index in validOffsets.reversed() {
            values.remove(at: index)
        }
        let removedBeforeDestination = validOffsets.filter { $0 < destination }.count
        let insertionIndex = min(max(destination - removedBeforeDestination, 0), values.count)
        values.insert(contentsOf: moving, at: insertionIndex)
        return true
    }
}
