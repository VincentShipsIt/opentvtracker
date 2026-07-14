import SwiftUI

struct FeaturedMediaCard: View {
    let title: MediaTitle
    let onTrailer: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            BackdropArtwork(title: title)
                .frame(maxWidth: .infinity)
                .frame(height: 270)

            LinearGradient(
                colors: [.clear, .black.opacity(0.32), .black.opacity(0.92)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(.rect(cornerRadius: AppTheme.cardRadius))

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
                    if title.trailerURL != nil {
                        Button("Trailer", systemImage: "play.fill", action: onTrailer)
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

struct ServiceFilterChip: View {
    @Environment(AppModel.self) private var model
    let provider: StreamingProvider

    var body: some View {
        Button {
            model.toggleProvider(provider.id)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: provider.symbol)
                Text(provider.name)
                if model.isProviderSelected(provider.id) {
                    Image(systemName: "checkmark.circle.fill")
                }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(
            model.isProviderSelected(provider.id) ? brandColor : Color.secondary.opacity(0.10),
            in: Capsule()
        )
        .foregroundStyle(model.isProviderSelected(provider.id) ? Color.white : Color.primary)
        .overlay {
            Capsule().strokeBorder(model.isProviderSelected(provider.id) ? .white.opacity(0.18) : .clear)
        }
        .accessibilityAddTraits(model.isProviderSelected(provider.id) ? .isSelected : [])
    }

    private var brandColor: Color {
        provider.brandHex.map { Color(hex: $0) } ?? .accentColor
    }
}
