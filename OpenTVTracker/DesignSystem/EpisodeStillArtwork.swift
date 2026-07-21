import SwiftUI

struct EpisodeStillArtwork: View {
    @Environment(\.allowsRemoteArtwork) private var allowsRemoteArtwork
    let url: URL?
    let fallbackURL: URL?
    let showTitle: String
    let episodeLabel: String
    let palette: PosterPalette

    init(
        url: URL?,
        fallbackURL: URL? = nil,
        showTitle: String,
        episodeLabel: String,
        palette: PosterPalette
    ) {
        self.url = url
        self.fallbackURL = fallbackURL
        self.showTitle = showTitle
        self.episodeLabel = episodeLabel
        self.palette = palette
    }

    var body: some View {
        Group {
            if allowsRemoteArtwork, let artworkURL = url ?? fallbackURL {
                AsyncImage(
                    url: artworkURL,
                    transaction: Transaction(animation: .easeInOut(duration: 0.2))
                ) { phase in
                    switch phase {
                    case .empty:
                        placeholder.overlay { ProgressView().tint(.white) }
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .transition(.opacity)
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .compositingGroup()
        .clipShape(.rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.white.opacity(0.14))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Still from \(showTitle), \(episodeLabel)")
    }

    private var placeholder: some View {
        LinearGradient(
            colors: [Color(hex: palette.primaryHex), Color(hex: palette.secondaryHex)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "play.rectangle.fill")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.78))
        }
    }
}

struct EpisodeSpoilerArtworkPlaceholder: View {
    let label: String?

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.secondary.opacity(0.14))
            .overlay {
                if let label {
                    Label(label, systemImage: "eye.slash.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "eye.slash.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("Episode artwork hidden until watched")
    }
}
