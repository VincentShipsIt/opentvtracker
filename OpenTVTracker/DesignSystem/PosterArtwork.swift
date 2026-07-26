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

    var body: some View {
        // It has to be the caller's frame that decides how tall this gets, never the image:
        // a view that sizes itself from `scaledToFill` reports the scaled height and blows
        // the hero out of shape.
        NetworkArtwork(
            url: title.backdropURL ?? title.posterURL,
            title: title,
            style: .backdrop
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // A 2:3 poster centre-cropped into a 16:9 slot loses its top and bottom thirds —
        // exactly where posters put their title treatment and billing block — and what
        // survives reads as a botched crop. Blurring the stand-in turns it into an ambient
        // wash of the title's own colours: nothing is legible, so nothing looks cut off.
        // Wherever a hero shows the poster inset, that copy is still sharp.
        .blur(radius: isPosterStandIn ? 26 : 0)
        // Blur samples past the edges, so the outer band fades towards transparent. Scaling
        // up pushes that soft margin outside the frame before `clipped` trims back to it.
        .scaleEffect(isPosterStandIn ? 1.22 : 1)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Backdrop artwork for \(title.title)")
    }

    /// True only when a real portrait poster is filling a landscape slot. The gradient
    /// placeholder has the show's name drawn into it and offline mode always renders it, so
    /// blurring in either case would smear text rather than artwork.
    private var isPosterStandIn: Bool {
        allowsRemoteArtwork && title.backdropURL == nil && title.posterURL != nil
    }
}

private struct NetworkArtwork: View {
    @Environment(\.allowsRemoteArtwork) private var allowsRemoteArtwork
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let url: URL?
    let title: MediaTitle
    let style: ArtworkStyle

    var body: some View {
        Group {
            if allowsRemoteArtwork, let url {
                AsyncImage(url: url, transaction: artworkTransaction) { phase in
                    switch phase {
                    case .empty:
                        placeholder
                            .overlay { ProgressView().tint(.white) }
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

            Circle()
                .fill(.white.opacity(0.10))
                .frame(width: style == .poster ? 150 : 260, height: style == .poster ? 150 : 260)
                .offset(x: 50, y: -90)

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
