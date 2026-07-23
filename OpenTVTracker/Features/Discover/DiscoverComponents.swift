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
