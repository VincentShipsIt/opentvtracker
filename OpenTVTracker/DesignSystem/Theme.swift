import SwiftUI

enum AppTheme {
    static let horizontalPadding: CGFloat = 20
    static let cardRadius: CGFloat = 24
    static let compactRadius: CGFloat = 16
    static let sectionSpacing: CGFloat = 28
}

enum AccessibleForeground: Equatable {
    case dark
    case light

    var color: Color {
        switch self {
        case .dark: .black
        case .light: .white
        }
    }
}

enum AppAccessibility {
    static let minimumTouchTarget: CGFloat = 44

    static func displayedInitials(_ initials: String) -> String {
        String(initials.filter { !$0.isWhitespace }.prefix(2)).uppercased()
    }

    static func readableForeground(forHex hex: String?) -> AccessibleForeground {
        guard let luminance = relativeLuminance(forHex: hex) else { return .light }
        let darkContrast = (luminance + 0.05) / 0.05
        let lightContrast = 1.05 / (luminance + 0.05)
        return darkContrast >= lightContrast ? .dark : .light
    }

    private static func relativeLuminance(forHex hex: String?) -> Double? {
        guard let hex else { return nil }
        let normalized = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard normalized.count == 6 else { return nil }

        var value: UInt64 = 0
        guard Scanner(string: normalized).scanHexInt64(&value) else { return nil }
        let red = linearized(Double((value >> 16) & 0xFF) / 255)
        let green = linearized(Double((value >> 8) & 0xFF) / 255)
        let blue = linearized(Double(value & 0xFF) / 255)
        return (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
    }

    private static func linearized(_ channel: Double) -> Double {
        channel <= 0.03928
            ? channel / 12.92
            : pow((channel + 0.055) / 1.055, 2.4)
    }
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

struct AdaptiveHeroSurface<Artwork: View, Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    private let minimumHeight: CGFloat
    private let cornerRadius: CGFloat
    private let contentInsets: EdgeInsets
    private let artwork: Artwork
    private let content: Content

    init(
        minimumHeight: CGFloat,
        cornerRadius: CGFloat = AppTheme.cardRadius,
        contentInsets: EdgeInsets = EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18),
        @ViewBuilder artwork: () -> Artwork,
        @ViewBuilder content: () -> Content
    ) {
        self.minimumHeight = minimumHeight
        self.cornerRadius = cornerRadius
        self.contentInsets = contentInsets
        self.artwork = artwork()
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(minHeight: minimumHeight)

            artwork
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            LinearGradient(
                colors: gradientColors,
                startPoint: .top,
                endPoint: .bottom
            )
            .accessibilityHidden(true)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(contentInsets)
        }
        .frame(maxWidth: .infinity)
        .compositingGroup()
        .clipShape(.rect(cornerRadius: cornerRadius))
    }

    private var gradientColors: [Color] {
        if reduceTransparency {
            return [.black.opacity(0.55), .black.opacity(0.92), .black]
        }
        if contrast == .increased {
            return [.clear, .black.opacity(0.78), .black]
        }
        return [.clear, .black.opacity(0.32), .black.opacity(0.94)]
    }
}

private struct MinimumTouchTargetModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(
                minWidth: AppAccessibility.minimumTouchTarget,
                minHeight: AppAccessibility.minimumTouchTarget
            )
            .contentShape(.rect)
    }
}

extension View {
    func minimumTouchTarget() -> some View {
        modifier(MinimumTouchTargetModifier())
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
        .accessibilityAddTraits(.isHeader)
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
