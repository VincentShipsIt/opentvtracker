import SwiftUI

/// The banner Today shows when the queue is empty.
///
/// It occupies the same slot as `UpNextHero` and is now built the same way: full-bleed
/// backdrop, bottom-anchored scrim, white content. It used to be an inset glass card with a
/// 72pt poster and two full-width labelled buttons, so the home screen changed shape
/// entirely depending on whether anything was up next — and the one title the app is
/// actively pitching got the smallest artwork on the screen.
struct TodayRecommendationCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: MediaTitle
    let onAdd: () -> Void
    let onOpenDiscover: () -> Void
    let onHide: () -> Void

    var body: some View {
        AdaptiveHeroSurface(
            minimumHeight: 380,
            cornerRadius: 0,
            contentInsets: EdgeInsets(
                top: 24,
                leading: AppTheme.horizontalPadding,
                bottom: 24,
                trailing: AppTheme.horizontalPadding
            )
        ) {
            BackdropArtwork(title: title, cornerRadius: 0)
                .accessibilityHidden(true)
        } content: {
            VStack(alignment: .leading, spacing: 13) {
                Label("A pick for tonight", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                NavigationLink(value: title) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(title.title)
                            .font(.largeTitle.weight(.black))
                            .foregroundStyle(.white)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                            .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
                        Text(title.recommendationReason ?? "A strong match on one of your selected services.")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                            .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                actionRow
            }
        }
        .accessibilityIdentifier("today.recommendation")
    }

    /// Icons only, so the row never wraps and never competes with the title for the eye.
    /// Hide sits behind a spacer rather than beside add: it is the one control here that
    /// takes the pick away, and it should not be a mis-tap away from keeping it.
    private var actionRow: some View {
        HStack(spacing: 12) {
            iconButton("Add to watchlist", systemImage: "plus", isProminent: true, action: onAdd)
                .accessibilityHint("Adds this pick to your watchlist")
                .accessibilityIdentifier("today.recommendation.add")

            iconButton("Explore Discover", systemImage: "magnifyingglass", action: onOpenDiscover)
                .accessibilityHint("Opens Discover to browse more titles")

            Spacer()

            iconButton("Hide this pick", systemImage: "xmark", action: onHide)
                .accessibilityHint("Stops recommending this title and suggests another")
                .accessibilityIdentifier("today.recommendation.hide")
        }
    }

    /// Exactly one touch target wide, drawn rather than derived.
    ///
    /// These were bordered buttons wrapping a `minimumTouchTarget()` label under
    /// `controlSize(.large)`, and those three compound: the style padded a frame that was
    /// already 44pt and the large size scaled that padding again, so a row of "small icon
    /// buttons" rendered as three circles the better part of 80pt across. Sizing the circle
    /// itself keeps the target honest at 44pt and stops the styles arguing about it.
    private func iconButton(
        _ label: String,
        systemImage: String,
        isProminent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isProminent ? .black : .white)
                .frame(
                    width: AppAccessibility.minimumTouchTarget,
                    height: AppAccessibility.minimumTouchTarget
                )
                .background {
                    Circle()
                        .fill(isProminent ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.16)))
                        .overlay {
                            if !isProminent {
                                Circle().strokeBorder(.white.opacity(0.35))
                            }
                        }
                }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct TodayRecoveryCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let hasSelectedServices: Bool
    let catalogError: String?
    let onManageServices: () -> Void
    let onOpenDiscover: () -> Void

    var body: some View {
        GlassSurface(tint: .orange) {
            VStack(spacing: 14) {
                ContentUnavailableView(title, systemImage: "sparkles.tv", description: Text(description))

                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(spacing: 10) { actionButtons }
                    } else {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 10) { actionButtons }
                            VStack(spacing: 10) { actionButtons }
                        }
                    }
                }
                .padding(.horizontal, 18)
            }
            .padding(.vertical, 20)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button("Manage services", systemImage: "slider.horizontal.3", action: onManageServices)
            .adaptiveGlassButton(prominent: !hasSelectedServices)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            .frame(maxWidth: .infinity)
        Button("Open Discover", systemImage: "magnifyingglass", action: onOpenDiscover)
            .adaptiveGlassButton(prominent: hasSelectedServices)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            .frame(maxWidth: .infinity)
    }

    private var title: String {
        if !hasSelectedServices { return "Choose your streaming services" }
        if catalogError != nil { return "Catalog temporarily unavailable" }
        return "Find something for tonight"
    }

    private var description: String {
        if !hasSelectedServices {
            return "Add subscriptions you already have, then OpenTV can explain recommendations that are available to you."
        }
        if catalogError != nil {
            return "Your local library still works. Retry in Discover or choose something already saved."
        }
        return "Search the catalog or add a recommendation to build your Up Next queue."
    }
}
