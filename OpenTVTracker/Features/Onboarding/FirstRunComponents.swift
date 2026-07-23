import SwiftUI

struct FirstRunHeader: View {
    let step: FirstRunStep

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView(value: Double(step.rawValue + 1), total: Double(FirstRunStep.allCases.count))
                .accessibilityLabel("Setup progress")
                .accessibilityValue("Step \(step.rawValue + 1) of \(FirstRunStep.allCases.count)")

            Text(step.title)
                .font(.title.weight(.bold))
            Text(step.subtitle)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppTheme.horizontalPadding)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

struct FirstRunFooter: View {
    let step: FirstRunStep
    let selectedTitleCount: Int
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            if step == .titles, selectedTitleCount < 2 {
                Text("Add \(2 - selectedTitleCount) more, or continue and discover titles later.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    actionButtons
                }
                VStack(spacing: 10) {
                    actionButtons
                }
            }
        }
        .padding(.horizontal, AppTheme.horizontalPadding)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var actionButtons: some View {
        if step != .services {
            Button("Back", action: onBack)
                .frame(maxWidth: .infinity)
                .adaptiveGlassButton()
        }

        Button(step == .partner ? "Finish setup" : "Continue", action: onContinue)
            .frame(maxWidth: .infinity)
            .adaptiveGlassButton(prominent: true)
            .accessibilityIdentifier("first-run.continue")
    }
}

struct FirstRunProviderRow: View {
    let provider: StreamingProvider
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: provider.symbol)
                    .frame(width: 38, height: 38)
                    .background(provider.brandHex.map { Color(hex: $0) } ?? .accentColor, in: Circle())
                    .foregroundStyle(.white)
                Text(provider.name)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct FirstRunSearchField: View {
    @Binding var searchText: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search shows and movies", text: $searchText)
                .focused($isFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button("Clear search", systemImage: "xmark.circle.fill") {
                    searchText = ""
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .minimumTouchTarget()
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .background(Color(.secondarySystemBackground), in: Capsule())
        .overlay { Capsule().strokeBorder(.primary.opacity(0.08)) }
    }
}

struct FirstRunSearchPrompt: View {
    var body: some View {
        GlassSurface(cornerRadius: AppTheme.compactRadius) {
            ContentUnavailableView(
                "Build your starting queue",
                systemImage: "sparkles.tv",
                description: Text("Search for a couple of favorites, current shows, or movies you want to watch.")
            )
            .padding(.vertical, 24)
        }
    }
}

struct FirstRunCatalogError: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        GlassSurface(cornerRadius: AppTheme.compactRadius, tint: .orange) {
            VStack(spacing: 14) {
                ContentUnavailableView(
                    "Catalog unavailable",
                    systemImage: "wifi.exclamationmark",
                    description: Text(message)
                )
                Button("Try again", systemImage: "arrow.clockwise", action: retry)
                    .adaptiveGlassButton(prominent: true)
                Text("Your local library still works, and you can add titles from Discover later.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 18)
        }
    }
}

struct FirstRunTitleRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: MediaTitle
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        GlassSurface(cornerRadius: AppTheme.compactRadius) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 14) {
                            artwork
                            metadata
                        }
                        selectionButton(labelStyle: .titleAndIcon)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    HStack(spacing: 14) {
                        artwork
                        metadata
                        Spacer(minLength: 0)
                        selectionButton(labelStyle: .iconOnly)
                    }
                }
            }
            .padding(12)
        }
    }

    private var artwork: some View {
        PosterArtwork(title: title, cornerRadius: 10)
            .frame(width: 56, height: 84)
            .accessibilityHidden(true)
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.title)
                .font(.headline)
                .lineLimit(2)
            Text("\(title.year) · \(title.kind.label)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let provider = title.providers.first {
                Text(provider.name)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func selectionButton(labelStyle: LabelStyleOption) -> some View {
        Button(action: action) {
            if labelStyle == .iconOnly {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
            } else {
                Label(
                    isSelected ? "Remove" : "Add",
                    systemImage: isSelected ? "checkmark.circle.fill" : "plus.circle"
                )
            }
        }
        .font(.title2)
        .foregroundStyle(isSelected ? Color.green : Color.accentColor)
        .minimumTouchTarget()
        .accessibilityLabel(isSelected ? "Remove \(title.title)" : "Add \(title.title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private enum LabelStyleOption: Equatable {
        case iconOnly
        case titleAndIcon
    }
}
