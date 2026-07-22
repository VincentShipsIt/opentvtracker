import SwiftUI

struct FeaturedMediaCard: View {
    let title: MediaTitle
    let onTrailer: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                BackdropArtwork(title: title)
                    .frame(width: geometry.size.width, height: geometry.size.height)

                LinearGradient(
                    colors: [.clear, .black.opacity(0.32), .black.opacity(0.92)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 10) {
                    if let provider = title.providers.first {
                        ProviderBadge(provider: provider)
                    }
                    Text(title.title)
                        .font(.largeTitle.weight(.black))
                        .foregroundStyle(.white)
                    Text(title.recommendationReason ?? title.synopsis)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.86))
                        .lineLimit(2)

                    HStack(spacing: 10) {
                        if let sourceURL = title.trailerURL,
                           TrailerPresentation(title: title.title, sourceURL: sourceURL) != nil {
                            Button("Trailer", systemImage: "play.fill", action: onTrailer)
                                .buttonStyle(.borderedProminent)
                                .tint(.white)
                                .foregroundStyle(.black)
                        } else if let sourceURL = title.trailerURL,
                                  let externalURL = TrailerURLNormalizer.safeExternalURL(sourceURL) {
                            Link(destination: externalURL) {
                                Label("Open trailer", systemImage: "arrow.up.right.square")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.white)
                            .foregroundStyle(.black)
                        }

                        NavigationLink(value: title) {
                            Label("Details", systemImage: "info.circle")
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    }
                }
                .padding(18)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .compositingGroup()
            .clipShape(.rect(cornerRadius: AppTheme.cardRadius))
        }
        .frame(height: 270)
        .accessibilityElement(children: .contain)
    }
}

struct MediaShelf: View {
    let title: String
    let subtitle: String
    let titles: [MediaTitle]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: title, subtitle: subtitle)
                .padding(.horizontal, AppTheme.horizontalPadding)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 14) {
                    ForEach(titles) { title in
                        NavigationLink(value: title) {
                            PosterShelfCard(title: title)
                                .frame(width: 152)
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
        .background(brandColor, in: Capsule())
        .foregroundStyle(.white)
        .accessibilityLabel("Available on \(provider.name)")
    }

    private var brandColor: Color {
        provider.brandHex.map { Color(hex: $0) } ?? .accentColor
    }
}
