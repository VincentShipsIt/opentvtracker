import SwiftUI

enum AppTheme {
    static let horizontalPadding: CGFloat = 20
    static let cardRadius: CGFloat = 24
    static let compactRadius: CGFloat = 16
    static let sectionSpacing: CGFloat = 28
}

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}

struct AmbientBackdrop: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
            RadialGradient(
                colors: [Color.accentColor.opacity(0.18), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 420
            )
            LinearGradient(
                colors: [Color.clear, Color.indigo.opacity(0.08)],
                startPoint: .top,
                endPoint: .bottomLeading
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct SectionHeading: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.title2.weight(.bold))
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct RatingLabel: View {
    let rating: Double

    var body: some View {
        Label(rating.formatted(.number.precision(.fractionLength(1))), systemImage: "star.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.yellow)
            .accessibilityLabel("Rated \(rating.formatted(.number.precision(.fractionLength(1)))) out of 10")
    }
}
