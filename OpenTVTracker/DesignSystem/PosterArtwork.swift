import SwiftUI

extension EnvironmentValues {
    @Entry var allowsRemoteArtwork = true
}

struct PosterArtwork: View {
    let title: MediaTitle
    var cornerRadius: CGFloat = AppTheme.compactRadius

    var body: some View {
        NetworkArtwork(
            url: title.posterURL,
            title: title,
            style: .poster
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .clipShape(.rect(cornerRadius: cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(.white.opacity(0.14))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Poster for \(title.title)")
    }
}

struct BackdropArtwork: View {
    @Environment(\.allowsRemoteArtwork) private var allowsRemoteArtwork
    let title: MediaTitle
    var cornerRadius: CGFloat = AppTheme.cardRadius

    /// Latches the moment a poster has had to stand in for missing landscape art.
    ///
    /// Catalog enrichment fills `backdropURL` for titles that arrive without one, and it
    /// lands while a detail screen is still animating in. Deriving the entire presentation
    /// from that one field meant the hero tore itself down at exactly that moment: the
    /// stand-in disappeared, the `AsyncImage` reset to a spinner because its URL had
    /// changed, and only then did the real artwork fade in. Latching keeps the poster on
    /// screen as a floor, so the upgrade is a plain cross-fade
    /// over something that never moves.
    @State private var hasStoodInForBackdrop = false

    var body: some View {
        ZStack {
            if showsPosterFloor {
                posterFloor
            }

            if allowsRemoteArtwork, let backdropURL = title.backdropURL {
                // Transparent until it has pixels, so the poster below is what shows during
                // the load rather than a second placeholder and spinner stacked over it.
                NetworkArtwork(
                    url: backdropURL,
                    title: title,
                    style: .backdrop,
                    showsPlaceholder: !showsPosterFloor
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .clipped()
        .clipShape(.rect(cornerRadius: cornerRadius))
        .overlay {
            // Only when this view rounds its own corners. Callers pass `cornerRadius: 0`
            // when the artwork is a fill inside something else's clip, and a square stroke
            // there draws a hard box straight across the container's rounded edge.
            if cornerRadius > 0 {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.white.opacity(0.12))
            }
        }
        .onChange(of: title.backdropURL, initial: true) { _, resolved in
            if resolved == nil { hasStoodInForBackdrop = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Backdrop artwork for \(title.title)")
    }

    /// It has to be the caller's frame that decides how tall this gets, never the image:
    /// a view that sizes itself from `scaledToFill` reports the scaled height and blows the
    /// hero out of shape.
    private var posterFloor: some View {
        NetworkArtwork(url: title.posterURL, title: title, style: .backdrop)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Present whenever there is no landscape art to show, and kept afterwards for any
    /// hero that once had to stand one in — a floor costs nothing behind an opaque image,
    /// and removing it is what used to make the swap visible.
    private var showsPosterFloor: Bool {
        !allowsRemoteArtwork || title.backdropURL == nil || hasStoodInForBackdrop
    }
}

private struct NetworkArtwork: View {
    @Environment(\.allowsRemoteArtwork) private var allowsRemoteArtwork
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let url: URL?
    let title: MediaTitle
    let style: ArtworkStyle
    /// Off for artwork layered over something that already fills the frame: a second
    /// gradient and spinner on top of a visible image is noise, and dropping to it while a
    /// better image loads is the swap this layering exists to hide.
    var showsPlaceholder = true

    /// `Color.clear` takes whatever size it is proposed and reports that back unchanged, so
    /// the artwork in its overlay is handed a size it has no vote in.
    ///
    /// Sizing from the content instead is what put a zoom on every thumbnail in the app.
    /// `AsyncImage` reports the size of whichever phase it is currently showing, and the
    /// phases disagree: the placeholder reports the fixed circle drawn into it, while a
    /// `scaledToFill` image reports the *scaled* image. The swap between them runs inside
    /// `artworkTransaction`, so SwiftUI animated that disagreement, and a fill-scaled image
    /// redrawn against a frame still in motion reads as zooming in and settling back.
    /// `AdaptiveHeroSurface` moved its artwork into `.background` for the same reason —
    /// doing it here fixes every poster, backdrop and thumbnail in one place. All callers
    /// hand this view a bounded proposal (a fixed frame, a grid column, or an aspect ratio
    /// over a definite width), so `Color.clear`'s ideal size is never consulted.
    var body: some View {
        Color.clear
            .overlay { phases }
            .clipped()
    }

    @ViewBuilder
    private var phases: some View {
        if allowsRemoteArtwork, let url {
            AsyncImage(url: url, transaction: artworkTransaction) { phase in
                switch phase {
                case .empty:
                    if showsPlaceholder {
                        placeholder
                            .overlay { ProgressView().tint(.white) }
                    } else {
                        Color.clear
                    }
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .transition(reduceMotion ? .identity : .opacity)
                case .failure:
                    unavailable
                @unknown default:
                    unavailable
                }
            }
        } else {
            unavailable
        }
    }

    @ViewBuilder
    private var unavailable: some View {
        if showsPlaceholder {
            placeholder
        } else {
            Color.clear
        }
    }

    private var artworkTransaction: Transaction {
        Transaction(animation: reduceMotion ? nil : .easeInOut(duration: 0.25))
    }

    private var placeholder: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color(hex: title.palette.primaryHex), Color(hex: title.palette.secondaryHex)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            // Decoration, so it hangs off the gradient rather than standing in the stack.
            // A fixed 150pt shape as a sibling made the whole placeholder report 150pt no
            // matter how small the slot was — the size the artwork used to animate away
            // from the moment the real image arrived.
            .overlay {
                Circle()
                    .fill(.white.opacity(0.10))
                    .frame(width: style == .poster ? 150 : 260, height: style == .poster ? 150 : 260)
                    .offset(x: 50, y: -90)
            }

            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: title.kind.symbol)
                    .font(.title3.weight(.semibold))
                Text(title.title)
                    .font(style == .poster ? .headline.weight(.bold) : .title2.weight(.bold))
                    .lineLimit(3)
            }
            .foregroundStyle(.white)
            .padding(14)
        }
    }
}

private enum ArtworkStyle: Equatable {
    case poster
    case backdrop
}
