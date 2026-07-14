import SwiftUI

struct GlassSurface<Content: View>: View {
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
        if #available(iOS 26, *) {
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
