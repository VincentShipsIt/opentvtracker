import SwiftUI

struct TodayHeader: View {
    let memberName: String
    let onOpenLibrary: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.largeTitle.weight(.bold))
                Text(.now, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(action: onOpenLibrary) {
                Label("Open Library", systemImage: "person.crop.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 34))
            }
            .accessibilityHint("Opens your private history, library, and settings")
            .accessibilityIdentifier("today.library")
            .minimumTouchTarget()
        }
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

struct TodayRecommendationCard: View {
    let title: MediaTitle
    let onAdd: () -> Void
    let onOpenDiscover: () -> Void

    var body: some View {
        GlassSurface(tint: .indigo) {
            VStack(alignment: .leading, spacing: 14) {
                Label("A pick for tonight", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(.indigo)

                NavigationLink(value: title) {
                    HStack(spacing: 14) {
                        PosterArtwork(title: title, cornerRadius: 10)
                            .frame(width: 72, height: 108)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(title.title)
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.primary)
                            Text(title.recommendationReason ?? "A strong match on one of your selected services.")
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
                .buttonStyle(.plain)

                HStack {
                    Button("Add to watchlist", systemImage: "plus", action: onAdd)
                        .adaptiveGlassButton(prominent: true)
                    Button("Explore Discover", systemImage: "magnifyingglass", action: onOpenDiscover)
                        .adaptiveGlassButton()
                }
            }
            .padding(18)
        }
        .accessibilityIdentifier("today.recommendation")
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

                HStack {
                    Button("Manage services", systemImage: "slider.horizontal.3", action: onManageServices)
                        .adaptiveGlassButton(prominent: !hasSelectedServices)
                    Button("Open Discover", systemImage: "magnifyingglass", action: onOpenDiscover)
                        .adaptiveGlassButton(prominent: hasSelectedServices)
                }
            }
            .padding(.vertical, 20)
        }
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
