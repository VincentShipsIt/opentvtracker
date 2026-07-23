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
        } else {
            if let tint {
                content
                    .glassEffect(
                        .regular.tint(tint.opacity(0.22)),
                        in: .rect(cornerRadius: cornerRadius)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(.primary.opacity(contrast == .increased ? 0.38 : 0))
                    }
            } else {
                content
                    .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(.primary.opacity(contrast == .increased ? 0.38 : 0))
                    }
            }
        }
    }
}

struct GlassButtonModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    let prominent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            if prominent {
                touchSized(content).buttonStyle(.borderedProminent)
            } else {
                touchSized(content).buttonStyle(.bordered)
            }
        } else if prominent {
            touchSized(content).buttonStyle(.glassProminent)
        } else {
            touchSized(content).buttonStyle(.glass)
        }
    }

    private func touchSized(_ content: Content) -> some View {
        content.minimumTouchTarget()
    }
}

extension View {
    func adaptiveGlassButton(prominent: Bool = false) -> some View {
        modifier(GlassButtonModifier(prominent: prominent))
    }
}
