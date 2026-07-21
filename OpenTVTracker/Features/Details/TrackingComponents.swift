import SwiftUI

struct MediaProgressRow: View {
    let title: MediaTitle
    let summary: MediaProgressSummary
    var subtitle: String?

    var body: some View {
        GlassSurface(cornerRadius: AppTheme.compactRadius, tint: Color(hex: title.palette.primaryHex)) {
            HStack(spacing: 14) {
                PosterArtwork(title: title, cornerRadius: 10)
                    .frame(width: 68, height: 96)
                    .clipped()
                    .clipShape(.rect(cornerRadius: 10))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title.title)
                        .font(.headline)
                        .lineLimit(2)

                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Text(summary.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(2)

                    ProgressView(value: summary.fraction)
                        .tint(Color.accentColor)
                        .accessibilityLabel("Viewing progress")
                        .accessibilityValue(summary.label)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(12)
        }
        .accessibilityElement(children: .combine)
    }
}

struct MediaProgressPosterCard: View {
    let title: MediaTitle
    let summary: MediaProgressSummary
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottom) {
                PosterArtwork(title: title, cornerRadius: 14)
                    .aspectRatio(0.68, contentMode: .fit)

                ProgressView(value: summary.fraction)
                    .tint(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 7)
                    .accessibilityLabel("Viewing progress")
                    .accessibilityValue(summary.label)
            }

            Text(title.title)
                .font(.headline)
                .lineLimit(1)

            Text(subtitle ?? summary.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

struct TrackingSummaryCard: View {
    let title: MediaTitle
    let watchedEpisodeCount: Int
    let totalEpisodeCount: Int

    var body: some View {
        GlassSurface(tint: Color(hex: title.palette.primaryHex)) {
            HStack(spacing: 15) {
                PosterArtwork(title: title, cornerRadius: 12)
                    .frame(width: 76, height: 112)

                VStack(alignment: .leading, spacing: 8) {
                    Text(title.title)
                        .font(.title2.weight(.black))
                        .lineLimit(2)

                    Label(title.state.label, systemImage: title.state.symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    progress
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var progress: some View {
        if title.kind == .series, totalEpisodeCount > 0 {
            Text("\(watchedEpisodeCount) of \(totalEpisodeCount) episodes watched")
                .font(.caption)
                .foregroundStyle(.secondary)
            ProgressView(value: Double(watchedEpisodeCount), total: Double(totalEpisodeCount))
                .tint(.accentColor)
        } else if title.kind == .series {
            Text(title.progress?.label ?? title.state.label)
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if title.kind == .movie {
            Text(title.state == .completed ? "Watched" : "Not watched yet")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct TrackingStatusSection: View {
    let selectedState: WatchState
    let onSelect: (WatchState) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Status")

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(WatchState.allCases, id: \.self) { state in
                    Button {
                        onSelect(state)
                    } label: {
                        Label(state.label, systemImage: state.symbol)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .adaptiveGlassButton(prominent: selectedState == state)
                    .accessibilityValue(selectedState == state ? "Selected" : "Not selected")
                }
            }
        }
    }

    private var columns: [GridItem] {
        [
            GridItem(.flexible(minimum: 0), spacing: 10),
            GridItem(.flexible(minimum: 0), spacing: 10)
        ]
    }
}

struct TrackingRatingSection: View {
    let rating: Double?
    let onRatingChange: (Double?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Your rating")

            GlassSurface(cornerRadius: AppTheme.compactRadius) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        ForEach(1...5, id: \.self) { star in
                            ratingButton(star)
                        }
                    }

                    HStack {
                        Text(ratingLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if rating != nil {
                            Button("Clear") { onRatingChange(nil) }
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
                .padding(14)
            }
        }
    }

    private func ratingButton(_ star: Int) -> some View {
        Button {
            let newRating = Double(star * 2)
            onRatingChange(rating == newRating ? nil : newRating)
        } label: {
            Image(systemName: ratingSymbol(for: star))
                .font(.title2)
                .foregroundStyle(.yellow)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Rate \(star) out of 5 stars")
        .accessibilityValue(rating.map { currentRating in
            let threshold = Double(star * 2)
            if currentRating >= threshold { return "Selected" }
            if currentRating >= threshold - 1 { return "Half selected" }
            return "Not selected"
        } ?? "Not selected")
    }

    private var ratingLabel: String {
        guard let rating else { return "Tap a star to rate" }
        return "\(rating.formatted(.number.precision(.fractionLength(1)))) / 10"
    }

    private func ratingSymbol(for star: Int) -> String {
        guard let rating else { return "star" }
        let threshold = Double(star * 2)
        if rating >= threshold { return "star.fill" }
        if rating >= threshold - 1 { return "star.leadinghalf.filled" }
        return "star"
    }
}

struct EpisodeSeasonsView: View {
    @Environment(AppModel.self) private var model
    let titleID: MediaTitle.ID

    var body: some View {
        ZStack {
            AmbientBackdrop()

            if let title, !regularSeasons.isEmpty {
                List {
                    ForEach(regularSeasons) { season in
                        NavigationLink(
                            value: SeasonEpisodesRoute(titleID: title.id, seasonID: season.id)
                        ) {
                            SeasonNavigationRow(
                                season: season,
                                watchedCount: model.watchedEpisodeCount(titleID: title.id, season: season)
                            )
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            } else {
                ContentUnavailableView(
                    "Episodes unavailable",
                    systemImage: "rectangle.stack.badge.exclamationmark"
                )
            }
        }
        .navigationTitle("Episodes")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var title: MediaTitle? {
        model.mediaTitle(withID: titleID)
    }

    private var regularSeasons: [SeasonSummary] {
        (title?.seasons ?? [])
            .filter { $0.number > 0 }
            .sorted { $0.number < $1.number }
    }
}

struct PersonalNoteEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let title: MediaTitle
    @State private var text: String

    init(title: MediaTitle) {
        self.title = title
        _text = State(initialValue: title.notes ?? "")
    }

    var body: some View {
        ZStack {
            AmbientBackdrop()

            VStack(alignment: .leading, spacing: 12) {
                Text("Only you can see this note.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextEditor(text: $text)
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityLabel("Private note about \(title.title)")

                Spacer()
            }
            .padding(AppTheme.horizontalPadding)
        }
        .navigationTitle("Private note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .onDisappear(perform: save)
    }

    private func save() {
        model.updateNotes(text, for: title.id)
    }
}
