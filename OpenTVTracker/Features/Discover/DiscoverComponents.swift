import SwiftUI

struct FeaturedMediaCard: View {
    let title: MediaTitle
    let onTrailer: () -> Void

    var body: some View {
        AdaptiveHeroSurface(minimumHeight: 270) {
            BackdropArtwork(title: title, cornerRadius: 0)
                .accessibilityHidden(true)
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                if let provider = title.providers.first {
                    ProviderBadge(provider: provider)
                }
                Text(title.title)
                    .font(.largeTitle.weight(.black))
                    .foregroundStyle(.white)
                Text(title.recommendationReason ?? title.synopsis)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(2, reservesSpace: false)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        actionButtons
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        actionButtons
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var actionButtons: some View {
        if let sourceURL = title.trailerURL,
           TrailerPresentation(title: title.title, sourceURL: sourceURL) != nil {
            Button("Trailer", systemImage: "play.fill", action: onTrailer)
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
                .minimumTouchTarget()
        } else if let sourceURL = title.trailerURL,
                  let externalURL = TrailerURLNormalizer.safeExternalURL(sourceURL) {
            Link(destination: externalURL) {
                Label("Open trailer", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
            .minimumTouchTarget()
        }

        NavigationLink(value: title) {
            Label("Details", systemImage: "info.circle")
        }
        .buttonStyle(.bordered)
        .tint(.white)
        .minimumTouchTarget()
    }
}

struct MediaShelf: View {
    let title: String
    let subtitle: String
    let titles: [MediaTitle]
    var showsRecommendationReasons = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: title, subtitle: subtitle)
                .padding(.horizontal, AppTheme.horizontalPadding)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(titles) { title in
                        NavigationLink(value: title) {
                            if showsRecommendationReasons {
                                RecommendationShelfCard(title: title)
                                    .frame(width: 176)
                            } else {
                                PosterShelfCard(title: title)
                                    .frame(width: 152)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, AppTheme.horizontalPadding)
                .padding(.bottom, 4)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct RecommendationShelfCard: View {
    let title: MediaTitle

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PosterArtwork(title: title)
                .aspectRatio(0.68, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    if let provider = title.providers.first {
                        ProviderBadge(provider: provider, compact: true)
                            .padding(8)
                    }
                }

            Text(title.title)
                .font(.headline)
                .lineLimit(1)
            Text(title.recommendationReason ?? "A strong match on one of your selected services.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens details for this recommendation")
    }
}

struct PosterShelfCard: View {
    let title: MediaTitle

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                PosterArtwork(title: title)
                    .aspectRatio(0.68, contentMode: .fit)
                if let provider = title.providers.first {
                    ProviderBadge(provider: provider, compact: true)
                        .padding(8)
                }
            }

            Text(title.title)
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: 6) {
                RatingLabel(rating: title.rating)
                Text("· \(title.runtimeMinutes) min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ProviderBadge: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let provider: StreamingProvider
    var compact = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: provider.symbol)
            if !compact {
                Text(provider.name)
            }
        }
        .font(.caption.weight(.bold))
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, 7)
        .background(badgeBackground, in: Capsule())
        .foregroundStyle(badgeForeground)
        .overlay {
            Capsule()
                .strokeBorder(contrast == .increased ? Color.white : .clear, lineWidth: 1)
        }
        .accessibilityLabel("Available on \(provider.name)")
    }

    private var brandColor: Color {
        provider.brandHex.map { Color(hex: $0) } ?? .accentColor
    }

    private var badgeBackground: Color {
        contrast == .increased ? .black : brandColor
    }

    private var badgeForeground: Color {
        if contrast == .increased {
            return .white
        }
        return AppAccessibility.readableForeground(forHex: provider.brandHex).color
    }
}

struct CatalogSearchCard: View {
    @Environment(AppModel.self) private var model
    let result: MediaTitle
    let spaceMode: AppSpaceMode

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            NavigationLink(value: title) {
                PosterShelfCard(title: title)
            }
            .buttonStyle(.plain)

            Label(availabilityLabel, systemImage: availabilitySymbol)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(availabilityColor)
                .lineLimit(1)

            if spaceMode == .shared {
                sharedSpaceAction
            } else if title.state.isCurrentViewingComplete {
                Label(title.state == .completed ? "Watched" : "Caught up", systemImage: title.state.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(title.state == .completed ? "Already watched" : "Currently caught up")
            } else {
                Button("Mark watched", systemImage: "checkmark.circle") {
                    model.markWatched(title.id)
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHint("Adds this title to your viewing history and recommendation profile")
            }
        }
    }

    @ViewBuilder
    private var sharedSpaceAction: some View {
        if model.isShared(title.id) {
            Label("In shared space", systemImage: "person.2.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Button("Add to shared", systemImage: "person.2.badge.plus") {
                model.toggleTogether(title.id)
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHint("Adds this title to your private shared space")
        }
    }

    private var title: MediaTitle {
        model.mediaTitle(withID: result.id) ?? result
    }

    private var selectedProviders: [StreamingProvider] {
        title.providers.filter { model.selectedProviderIDs.contains($0.id) }
    }

    private var availabilityLabel: String {
        if let provider = selectedProviders.first { return "On \(provider.name)" }
        if !title.providers.isEmpty { return "On other services" }
        return "Availability unknown"
    }

    private var availabilitySymbol: String {
        if !selectedProviders.isEmpty { return "checkmark.circle.fill" }
        if !title.providers.isEmpty { return "play.tv" }
        return "questionmark.circle"
    }

    private var availabilityColor: Color {
        selectedProviders.isEmpty ? .secondary : .green
    }
}
