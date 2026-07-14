import SwiftUI

struct PosterArtwork: View {
    let title: MediaTitle
    var cornerRadius: CGFloat = AppTheme.compactRadius

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color(hex: title.palette.primaryHex), Color(hex: title.palette.secondaryHex)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(.white.opacity(0.10))
                .frame(width: 150, height: 150)
                .offset(x: 50, y: -90)

            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: title.kind.symbol)
                    .font(.title3.weight(.semibold))
                    .accessibilityHidden(true)
                Text(title.title)
                    .font(.headline.weight(.bold))
                    .lineLimit(3)
            }
            .foregroundStyle(.white)
            .padding(14)
        }
        .clipShape(.rect(cornerRadius: cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(.white.opacity(0.14))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Poster for \(title.title)")
    }
}
