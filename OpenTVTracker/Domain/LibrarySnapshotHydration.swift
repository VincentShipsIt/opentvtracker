import Foundation

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
