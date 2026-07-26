import SwiftUI

/// Greeting only. The account button used to live here, which put a second row of
/// controls directly under the toolbar's own row — two tiers of icons for one screen.
/// It sits in the trailing toolbar group now, level with the rest of the chrome.
struct TodayHeader: View {
    let memberName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greeting)
                .font(.largeTitle.weight(.bold))
            Text(.now, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppTheme.horizontalPadding)
        .padding(.top, 12)
    }

    private var greeting: String {
        let name = memberName == "You" ? nil : memberName
        let prefix: String
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: prefix = "Good morning"
        case 12..<18: prefix = "Good afternoon"
        default: prefix = "Good evening"
        }
        return name.map { "\(prefix), \($0)" } ?? prefix
    }
}

/// The banner Today shows when the queue is empty.
///
/// It occupies the same slot as `UpNextHero` and is now built the same way: full-bleed
/// backdrop, bottom-anchored scrim, white content. It used to be an inset glass card with a
/// 72pt poster and two full-width labelled buttons, so the home screen changed shape
/// entirely depending on whether anything was up next — and the one title the app is
/// actively pitching got the smallest artwork on the screen.
struct TodayRecommendationCard: View {
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
                            .lineLimit(2)
                        Text(title.recommendationReason ?? "A strong match on one of your selected services.")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
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
        HStack(spacing: 10) {
            iconButton("Add to watchlist", systemImage: "plus", action: onAdd)
                .buttonStyle(.borderedProminent)
                .foregroundStyle(.black)
                .accessibilityHint("Adds this pick to your watchlist")
                .accessibilityIdentifier("today.recommendation.add")

            iconButton("Explore Discover", systemImage: "magnifyingglass", action: onOpenDiscover)
                .buttonStyle(.bordered)
                .accessibilityHint("Opens Discover to browse more titles")

            Spacer()

            iconButton("Hide this pick", systemImage: "xmark", action: onHide)
                .buttonStyle(.bordered)
                .accessibilityHint("Stops recommending this title and suggests another")
                .accessibilityIdentifier("today.recommendation.hide")
        }
        .controlSize(.large)
    }

    private func iconButton(
        _ label: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .minimumTouchTarget()
        }
        .tint(.white)
        .accessibilityLabel(label)
    }
}

struct TodayRecoveryCard: View {
    let hasSelectedServices: Bool
    let catalogError: String?
    let onManageServices: () -> Void
    let onOpenDiscover: () -> Void

    var body: some View {
        GlassSurface(tint: .orange) {
            VStack(spacing: 14) {
                ContentUnavailableView(title, systemImage: "sparkles.tv", description: Text(description))

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { actionButtons }
                    VStack(spacing: 10) { actionButtons }
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
            .lineLimit(1)
            .frame(maxWidth: .infinity)
        Button("Open Discover", systemImage: "magnifyingglass", action: onOpenDiscover)
            .adaptiveGlassButton(prominent: hasSelectedServices)
            .lineLimit(1)
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
