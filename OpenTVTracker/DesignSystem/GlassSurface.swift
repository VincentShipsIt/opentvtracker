import SwiftUI

struct GlassSurface<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    private let cornerRadius: CGFloat
    private let tint: Color?
    private let content: Content

    init(
        cornerRadius: CGFloat = AppTheme.cardRadius,
        tint: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        if reduceTransparency {
            content
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(.primary.opacity(contrast == .increased ? 0.34 : 0.14))
                }
        } else if #available(iOS 26, *) {
            if let tint {
                content
                    .glassEffect(
                        .regular.tint(tint.opacity(0.22)),
                        in: .rect(cornerRadius: cornerRadius)
                    )
            } else {
                content
                    .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(.white.opacity(0.12))
                }
        }
    }
}

struct GlassButtonModifier: ViewModifier {
    let prominent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

extension View {
    func adaptiveGlassButton(prominent: Bool = false) -> some View {
        modifier(GlassButtonModifier(prominent: prominent))
    }
}
