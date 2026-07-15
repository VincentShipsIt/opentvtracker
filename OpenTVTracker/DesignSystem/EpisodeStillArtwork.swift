import SwiftUI

struct EpisodeStillArtwork: View {
    @Environment(\.allowsRemoteArtwork) private var allowsRemoteArtwork
    let url: URL?
    let showTitle: String
    let episodeLabel: String
    let palette: PosterPalette

    var body: some View {
        Group {
            if allowsRemoteArtwork, let url {
                AsyncImage(
                    url: url,
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
