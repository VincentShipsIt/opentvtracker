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
    let title: MediaTitle
    var cornerRadius: CGFloat = AppTheme.cardRadius

    var body: some View {
        NetworkArtwork(
            url: title.backdropURL,
            title: title,
            style: .backdrop
        )
        .clipShape(.rect(cornerRadius: cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(.white.opacity(0.12))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Backdrop artwork for \(title.title)")
    }
}

private struct NetworkArtwork: View {
    @Environment(\.allowsRemoteArtwork) private var allowsRemoteArtwork
    let url: URL?
    let title: MediaTitle
    let style: ArtworkStyle

    var body: some View {
        Group {
            if allowsRemoteArtwork, let url {
                AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.25))) { phase in
                    switch phase {
                    case .empty:
                        placeholder
                            .overlay { ProgressView().tint(.white) }
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
