import SwiftUI

struct TogetherView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    private let sharingService: any PartnerSharingProviding
    @State private var presentedSheet: TogetherSheet?
    @State private var sharingAvailability: PartnerSharingAvailability?

    init(sharingService: any PartnerSharingProviding = CloudKitPartnerSharingService()) {
        self.sharingService = sharingService
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackdrop()

                ScrollView {
                    LazyVStack(spacing: AppTheme.sectionSpacing) {
                        experienceSections
                    }
                    .padding(.horizontal, AppTheme.horizontalPadding)
                    .padding(.top, 10)
                    .padding(.bottom, 32)
                }
            }
            .sheet(item: $presentedSheet) { sheet in
                switch sheet {
                case .invite:
                    PartnerInvitationView(
                        space: model.sharedSpace,
                        sharingService: sharingService
                    )
                }
            }
            .navigationDestination(for: MediaTitle.self) { title in
                MediaDetailView(titleID: title.id)
            }
            .task { await refreshSharingAvailability() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await refreshSharingAvailability() }
            }
        }
    }

    @ViewBuilder
    private var experienceSections: some View {
        switch model.togetherConnectionPhase {
        case .connected:
            connectedSections
        case .unconnected, .waitingForPartner, .revoked, .expired, .left:
            PartnerSetupHero(
                phase: model.togetherConnectionPhase,
                availability: sharingAvailability,
                space: model.sharedSpace,
                presentedSheet: $presentedSheet
            )
        }
    }

    @ViewBuilder
    private var connectedSections: some View {
        TogetherSpaceHeader(
            space: model.sharedSpace,
            availability: sharingAvailability,
            presentedSheet: $presentedSheet
        )

        if model.sharedTitles.isEmpty {
            TogetherSharedLibraryEmptyState()
        } else {
            if let sharedUpNextTitle {
                TogetherSharedUpNextSection(title: sharedUpNextTitle, space: model.sharedSpace)
            }

            if !remainingSharedTitles.isEmpty {
                TogetherSharedWatchlistSection(titles: remainingSharedTitles)
            }

            if !model.togetherActivity.isEmpty {
                TogetherRecentActivitySection(
                    activities: model.togetherActivity,
                    space: model.sharedSpace
                )
            }
        }

        analyticsLink
    }

    private var sharedUpNextTitle: MediaTitle? {
        model.upNext.first(where: { model.isShared($0.id) })
            ?? model.sharedTitles.first(where: { $0.state != .completed })
            ?? model.sharedTitles.first
    }

    private var remainingSharedTitles: [MediaTitle] {
        guard let sharedUpNextTitle else { return model.sharedTitles }
        return model.sharedTitles.filter { $0.id != sharedUpNextTitle.id }
    }

    private var analyticsLink: some View {
        NavigationLink {
            ViewingAnalyticsView(scope: .together)
        } label: {
            ViewingAnalyticsPreviewCard(
                summary: ViewingAnalyticsEngine.summarize(snapshot: model.snapshot, scope: .together)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("together.viewing-analytics")
    }

    private func refreshSharingAvailability() async {
        sharingAvailability = await sharingService.availability()
    }
}

#Preview {
    TogetherView(sharingService: PreviewPartnerSharingService())
        .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
        .environment(\.allowsRemoteArtwork, false)
}

private struct PreviewPartnerSharingService: PartnerSharingProviding {
    func availability() async -> PartnerSharingAvailability { .available }

    func inviteURL(for _: SharedSpace.ID) async throws -> URL {
        URL(string: "https://opentvtracker.dev/invite") ?? URL(fileURLWithPath: "/invite")
    }

    func revoke(spaceID _: SharedSpace.ID) async throws {}

    func leave(space _: SharedSpace) async throws {}
}
