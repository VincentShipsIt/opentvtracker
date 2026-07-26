import SwiftUI

/// Whether unwatched episodes hide their still, title, and summary.
///
/// This used to be unconditional, which meant a show you had never started rendered as a
/// column of blank grey rectangles — the spoiler protection was invisible and read as
/// missing artwork. It is a display preference for this iPhone, so it lives in
/// `@AppStorage` rather than the synced library snapshot, and it is **off** by default.
enum EpisodeSpoilerPolicy {
    static let hidesUnwatchedDetailsKey = "episode.hidesUnwatchedDetails"

    /// One rule for every surface: an episode reveals itself once you have watched it, or
    /// whenever the preference is off. Screens ask this instead of testing `isWatched`
    /// directly, so the four gates cannot drift apart.
    static func revealsDetails(isWatched: Bool, hidesUnwatchedDetails: Bool) -> Bool {
        isWatched || !hidesUnwatchedDetails
    }
}

struct EpisodeStillArtwork: View {
    @Environment(\.allowsRemoteArtwork) private var allowsRemoteArtwork
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                    transaction: artworkTransaction
                ) { phase in
                    switch phase {
                    case .empty:
                        placeholder.overlay { ProgressView().tint(.white) }
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .transition(reduceMotion ? .identity : .opacity)
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

    private var artworkTransaction: Transaction {
        Transaction(animation: reduceMotion ? nil : .easeInOut(duration: 0.2))
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

/// Season key art for a list row. Seasons and episode stills want the same treatment — fill,
/// clip, hairline border, palette gradient when there is nothing to load — so this delegates
/// rather than restating it, and falls back to the show's poster so a season with no art of
/// its own still carries the title's colour instead of going grey.
///
/// Unlike an episode still, this is never spoiler-sensitive: season art is marketing material
/// that shipped before the season aired, so it does not consult `EpisodeSpoilerPolicy`.
struct SeasonArtwork: View {
    let season: SeasonSummary
    let title: MediaTitle

    var body: some View {
        EpisodeStillArtwork(
            url: season.artworkURL,
            fallbackURL: title.posterURL,
            showTitle: title.title,
            episodeLabel: season.title,
            palette: title.palette
        )
        // The row it sits in already combines its children into one element that reads the
        // season name and progress, so an artwork label here would only add noise.
        .accessibilityHidden(true)
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
