import Foundation

struct ImportResolutionAlias: Codable, Hashable, Sendable {
    let kind: MediaKind
    let catalogID: Int
    /// Aliases persisted before catalog-source isolation are TMDB-only, so a
    /// missing value decodes as `.tmdb` via `resolvedMetadataSource`.
    let metadataSource: MetadataSource?

    init(kind: MediaKind, catalogID: Int, metadataSource: MetadataSource? = nil) {
        self.kind = kind
        self.catalogID = catalogID
        self.metadataSource = metadataSource
    }

    init(title: MediaTitle) {
        self.init(
            kind: title.kind,
            catalogID: title.catalogID,
            metadataSource: LibraryTransferService.resolvedMetadataSource(title)
        )
    }

    var resolvedMetadataSource: MetadataSource { metadataSource ?? .tmdb }

    func matches(_ title: MediaTitle) -> Bool {
        title.kind == kind
            && title.catalogID == catalogID
            && LibraryTransferService.resolvedMetadataSource(title) == resolvedMetadataSource
    }
}

struct LibrarySnapshot: Codable, Hashable, Sendable {
    var schemaVersion: Int?
    var titles: [MediaTitle]
    var sharedSpace: SharedSpace
    var selectedProviderIDs: Set<StreamingProvider.ID>?
    var allowsAIReranking: Bool?
    var streamingRegionCode: String?
    var contentLanguageCode: String?
    var contentLanguageSettingWasPresent: Bool?
    var diaryEntries: [ViewingDiaryEntry]?
    var traktSyncState: TraktSyncState?
    var reminderSettings: ReminderSettings?
    var importResolutionAliases: [String: ImportResolutionAlias]?
    var hasCompletedFirstRun: Bool?
    var lists: [MediaList]?

    init(
        titles: [MediaTitle],
        sharedSpace: SharedSpace,
        selectedProviderIDs: Set<StreamingProvider.ID>? = nil,
        allowsAIReranking: Bool = false,
        streamingRegionCode: String? = nil,
        contentLanguageCode: String? = nil,
        contentLanguageSettingWasPresent: Bool? = true,
        diaryEntries: [ViewingDiaryEntry]? = nil,
        reminderSettings: ReminderSettings = ReminderSettings(),
        importResolutionAliases: [String: ImportResolutionAlias]? = nil,
        traktSyncState: TraktSyncState? = nil,
        hasCompletedFirstRun: Bool? = nil,
        lists: [MediaList] = [],
        schemaVersion: Int = 7
    ) {
        self.schemaVersion = schemaVersion
        self.titles = titles
        self.sharedSpace = sharedSpace
        self.selectedProviderIDs = selectedProviderIDs
        self.allowsAIReranking = allowsAIReranking
        self.streamingRegionCode = streamingRegionCode
        self.contentLanguageCode = contentLanguageCode
        self.contentLanguageSettingWasPresent = contentLanguageSettingWasPresent
        self.diaryEntries = diaryEntries
        self.traktSyncState = traktSyncState
        self.reminderSettings = reminderSettings
        self.importResolutionAliases = importResolutionAliases
        self.hasCompletedFirstRun = hasCompletedFirstRun
        self.lists = lists
    }
}
extension LibrarySnapshot {
    static let empty = LibrarySnapshot(
        titles: [],
        sharedSpace: SharedSpace(
            id: "primary-partner-space",
            name: "Our space",
            members: [
                SpaceMember(id: "local-user", name: "You", initials: "YOU", isCurrentUser: true)
            ],
            titleIDs: [],
            activity: [],
            isCloudSharingEnabled: false,
            membershipState: .local,
            watchEvents: [],
            tasteProfiles: [],
            reactions: [],
            notes: [],
            conversationDeletions: [],
            isCurrentUserShareOwner: true
        ),
        diaryEntries: []
    )
}

/// Shared field mapping from a portable snapshot into live app state.
///
/// Keeps `AppModel` init / load / replaceLibrary aligned so preference and library fields
/// cannot drift between entry points.
enum LibrarySnapshotHydration {
    struct Preferences: Equatable, Sendable {
        var selectedProviderIDs: Set<StreamingProvider.ID>
        var allowsAIReranking: Bool
        var streamingRegionOverride: StreamingRegion?
        var contentLanguageOverride: ContentLanguage?
        var traktSyncState: TraktSyncState
        var reminderSettings: ReminderSettings
        var importResolutionAliases: [String: ImportResolutionAlias]
        var hasCompletedFirstRun: Bool
        var lists: [MediaList]
        var diaryEntries: [ViewingDiaryEntry]
        var sharedSpace: SharedSpace
    }

    static let defaultProviderIDs: Set<StreamingProvider.ID> = [
        StreamingProvider.netflix.id,
        StreamingProvider.primeVideo.id,
        StreamingProvider.appleTV.id
    ]

    static func preferences(
        from snapshot: LibrarySnapshot,
        defaultFirstRunCompleted: Bool
    ) -> Preferences {
        Preferences(
            selectedProviderIDs: snapshot.selectedProviderIDs ?? defaultProviderIDs,
            allowsAIReranking: snapshot.allowsAIReranking ?? false,
            streamingRegionOverride: snapshot.streamingRegionCode.flatMap(StreamingRegion.init(code:)),
            contentLanguageOverride: snapshot.contentLanguageCode.flatMap(ContentLanguage.init(code:)),
            traktSyncState: snapshot.traktSyncState ?? .empty,
            reminderSettings: snapshot.reminderSettings ?? ReminderSettings(),
            importResolutionAliases: snapshot.importResolutionAliases ?? [:],
            hasCompletedFirstRun: snapshot.hasCompletedFirstRun ?? defaultFirstRunCompleted,
            lists: snapshot.lists ?? [],
            diaryEntries: ViewingDiaryMigration.resolvedEntries(from: snapshot),
            sharedSpace: snapshot.sharedSpace
        )
    }
}
