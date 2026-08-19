import SwiftUI

enum FirstRunStep: Int, CaseIterable {
    case services
    case titles
    case partner

    var title: String {
        switch self {
        case .services: "Choose your services"
        case .titles: "Seed your Today screen"
        case .partner: "Watch together, privately"
        }
    }

    var subtitle: String {
        switch self {
        case .services: "Recommendations use subscriptions you already have."
        case .titles: "Add two or three shows or movies to make Today useful immediately."
        case .partner: "Invite one partner now, or keep everything personal and add them later."
        }
    }
}

struct FirstRunView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var step: FirstRunStep = .services
    @State private var searchText = ""
    @State private var showsPartnerInvitation = false
    let partnerSharingService: any PartnerSharingProviding

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackdrop()

                VStack(spacing: 0) {
                    FirstRunHeader(step: step)

                    ScrollView {
                        stepContent
                            .padding(.horizontal, AppTheme.horizontalPadding)
                            .padding(.vertical, 20)
                    }
                    // The footer floats over the scroll region rather than sitting
                    // beside it: an inset extends the scrollable area underneath, which
                    // is what gives its glass something to refract and earns the scroll
                    // edge effect. As a `VStack` sibling it had neither.
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        FirstRunFooter(
                            step: step,
                            selectedTitleCount: selectedTitles.count,
                            onBack: moveBack,
                            onContinue: moveForward
                        )
                    }
                }
            }
            // The partner step and the invitation sheet it presents belong to the shared
            // space, so the backdrop has to follow the step rather than stay personal.
            // `AmbientBackdrop` animates on this value, so advancing to the last step
            // cross-fades the ambient wash into the shared hue the controls already use.
            .environment(\.appSpaceMode, step == .partner ? .shared : .personal)
            .navigationTitle("Welcome to OpenTV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip setup") { finish() }
                }
            }
            .task(id: searchText) {
                guard step == .titles else { return }
                await model.searchCatalog(text: searchText)
            }
            .sheet(isPresented: $showsPartnerInvitation) {
                PartnerInvitationView(
                    space: model.sharedSpace,
                    sharingService: partnerSharingService
                )
            }
        }
        .interactiveDismissDisabled()
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .services:
            servicesStep
        case .titles:
            titlesStep
        case .partner:
            partnerStep
        }
    }

    private var servicesStep: some View {
        VStack(spacing: 16) {
            GlassSurface(cornerRadius: AppTheme.compactRadius, tint: .indigo) {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Local first", systemImage: "iphone")
                        .font(.headline)
                    Text("Your library and deterministic recommendations stay on this iPhone. No OpenTV account is required.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
            }

            GlassSurface(cornerRadius: AppTheme.compactRadius) {
                LazyVStack(spacing: 0) {
                    ForEach(StreamingProvider.supportedSubscriptions) { provider in
                        FirstRunProviderRow(
                            provider: provider,
                            isSelected: model.isProviderSelected(provider.id)
                        ) {
                            model.toggleProvider(provider.id)
                        }

                        if provider.id != StreamingProvider.supportedSubscriptions.last?.id {
                            Divider().padding(.leading, 58)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var titlesStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            FirstRunSearchField(searchText: $searchText)

            if !selectedTitles.isEmpty {
                Label(
                    "\(CountLabel.titles(selectedTitles.count)) added",
                    systemImage: "checkmark.circle.fill"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
                .accessibilityIdentifier("first-run.selected-count")
            }

            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                FirstRunSearchPrompt()
            } else if model.isSearchingCatalog, model.catalogSearchResults.isEmpty {
                ProgressView("Searching the catalog…")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
            } else if let error = model.catalogSearchError, model.catalogSearchResults.isEmpty {
                FirstRunCatalogError(message: error) {
                    Task { await model.searchCatalog(text: searchText) }
                }
            } else if model.catalogSearchResults.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(model.catalogSearchResults.prefix(12)) { result in
                        FirstRunTitleRow(
                            title: model.mediaTitle(withID: result.id) ?? result,
                            isSelected: model.mediaTitle(withID: result.id)?.personalWatchlist == true
                        ) {
                            model.toggleFirstRunTitle(result.id)
                        }
                    }
                }
            }
        }
    }

    private var partnerStep: some View {
        VStack(spacing: 18) {
            GlassSurface(cornerRadius: AppTheme.compactRadius, tint: .pink) {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "person.2.badge.gearshape.fill")
                        .font(.system(size: 46))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)

                    Text("One invitation-only space")
                        .font(.title2.weight(.bold))
                    Text("Your personal library stays separate. A partner joins through a private iCloud invitation without creating an OpenTV password.")
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Invitation-only", systemImage: "lock.shield")
                        Label("Private iCloud synchronization", systemImage: "icloud")
                        Label("Optional — add a partner anytime", systemImage: "clock")
                    }
                    .font(.subheadline.weight(.medium))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }

            Button("Invite a partner", systemImage: "person.badge.plus") {
                showsPartnerInvitation = true
            }
            .frame(maxWidth: .infinity)
            .adaptiveGlassButton(prominent: true)
            .accessibilityIdentifier("first-run.invite-partner")

            spaceSwitchHint

            Text("You can finish setup without inviting anyone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        // Onboarding runs outside `SpaceModeContainer`, so this step has to install the
        // shared-space tint itself — otherwise the prominent invite button renders in the
        // asset-catalog accent and reads blue inside an otherwise pink partner card.
        .tint(AppSpaceMode.shared.accent)
    }

    /// The only place the space switch is ever spelled out during first run.
    ///
    /// Shake is unnamed on the main screens, and the toolbar button is icon-only, so
    /// onboarding has to say both once, plainly, next to the explanation of what the
    /// shared space even is. Settings repeats the same two paths after first run.
    private var spaceSwitchHint: some View {
        GlassSurface(cornerRadius: AppTheme.compactRadius) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Moving between the two spaces", systemImage: "arrow.left.arrow.right")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Shake this iPhone", systemImage: "iphone.radiowaves.left.and.right")
                    // The toolbar button renders icon-only, so naming its label here would
                    // point at text the user never sees. Describe the glyph instead.
                    Label(
                        "Or tap the people icon at the top left",
                        systemImage: AppSpaceMode.shared.symbol
                    )
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("first-run.space-switch-hint")
    }

    private var selectedTitles: [MediaTitle] {
        model.titles.filter { $0.personalWatchlist == true }
    }

    private func moveBack() {
        guard let previous = FirstRunStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    private func moveForward() {
        guard let next = FirstRunStep(rawValue: step.rawValue + 1) else {
            finish()
            return
        }
        step = next
    }

    private func finish() {
        model.completeFirstRun()
        dismiss()
    }
}

#Preview {
    FirstRunView(partnerSharingService: PreviewPartnerSharingService())
        .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
        .environment(\.allowsRemoteArtwork, false)
}
