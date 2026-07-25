import SwiftUI

enum AppTheme {
    static let horizontalPadding: CGFloat = 20
    static let cardRadius: CGFloat = 24
    static let compactRadius: CGFloat = 16
    static let sectionSpacing: CGFloat = 28

    /// Gap between stacked chrome controls that belong to one another — a screen title
    /// and the pickers that scope it. Deliberately tighter than `sectionSpacing`, which
    /// separates unrelated content sections: a picker pushed 28pt off its own title
    /// stops reading as part of that title.
    static let controlSpacing: CGFloat = 12

    /// Standard poster ratio. `PosterArtwork` fills whatever bounds it is offered and
    /// clips at them, so a caller that constrains only width has to supply a ratio —
    /// an unbounded height lets the artwork paint over its neighbours. Use this rather
    /// than inventing a fixed height, which stops scaling once Dynamic Type collapses
    /// a grid to a single, much wider column.
    static let posterAspectRatio: CGFloat = 0.68
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

            LinearGradient(
                stops: scrimStops,
                startPoint: .top,
                endPoint: .bottom
            )
            .accessibilityHidden(true)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(contentInsets)
        }
        .frame(maxWidth: .infinity)
        // The artwork fills whatever the hero turns out to be and never argues about that
        // size — which is why it sits behind the stack rather than inside it. As a sibling
        // it *did* argue: `scaledToFill` reports the scaled image's size, so a portrait
        // poster standing in for a missing 16:9 backdrop stretched the hero to roughly
        // three times its declared height and slid the poster's own baked-in title down
        // into the content band, where it collided with the title this view draws. Behind
        // the stack the artwork is proposed the resolved size and centre-crops into it, so
        // the aspect ratio and `minimumHeight` above are what actually govern.
        .background {
            artwork
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
        .compositingGroup()
        .clipShape(.rect(cornerRadius: cornerRadius))
    }

    /// A bottom-anchored scrim, not an even top-to-bottom wash.
    ///
    /// Content here is bottom-aligned over a promotional still, and those routinely carry
    /// a title treatment or a billing block baked into the image. An evenly distributed
    /// gradient only reaches ~32% black at mid-height, which is not enough separation to
    /// guarantee the app's own text reads as the top layer. Holding the top third nearly
    /// clear keeps the artwork legible while the lower half ramps hard enough to settle
    /// that question whatever the image happens to contain.
    private var scrimStops: [Gradient.Stop] {
        if reduceTransparency {
            return stops([(0, 0.55), (0.45, 0.78), (0.75, 0.94), (1, 1)])
        }
        if contrast == .increased {
            return stops([(0, 0.16), (0.3, 0.48), (0.62, 0.86), (1, 1)])
        }
        return stops([(0, 0), (0.32, 0.08), (0.58, 0.55), (0.8, 0.86), (1, 0.97)])
    }

    private func stops(_ values: [(location: CGFloat, opacity: Double)]) -> [Gradient.Stop] {
        values.map { Gradient.Stop(color: .black.opacity($0.opacity), location: $0.location) }
    }
}

/// Every poster / card / tile grid in the app shares one shape: two flexible columns
/// that collapse to a single column at accessibility text sizes. Six call sites each
/// re-derived this `[GridItem]` array by hand and had already drifted apart on column
/// `minimum` and spacing. This is the single source of truth — callers vary only the
/// spacing and the cells, never the collapse rule.
struct AdaptiveGrid<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let rowSpacing: CGFloat?
    private let columnSpacing: CGFloat?
    private let minimumColumnWidth: CGFloat
    private let alignment: HorizontalAlignment
    private let content: Content

    init(
        rowSpacing: CGFloat? = nil,
        columnSpacing: CGFloat? = nil,
        minimumColumnWidth: CGFloat = 10,
        alignment: HorizontalAlignment = .center,
        @ViewBuilder content: () -> Content
    ) {
        self.rowSpacing = rowSpacing
        self.columnSpacing = columnSpacing
        self.minimumColumnWidth = minimumColumnWidth
        self.alignment = alignment
        self.content = content()
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: alignment, spacing: rowSpacing) {
            content
        }
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: minimumColumnWidth), spacing: columnSpacing),
            count: dynamicTypeSize.isAccessibilitySize ? 1 : 2
        )
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
    @Environment(\.appSpaceMode) private var spaceMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color(.systemBackground)
            RadialGradient(
                colors: [spaceMode.accent.opacity(0.22), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 420
            )
            LinearGradient(
                colors: [Color.clear, spaceMode.ambientWash.opacity(0.12)],
                startPoint: .top,
                endPoint: .bottomLeading
            )
        }
        .ignoresSafeArea()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: spaceMode)
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
