import SwiftUI

struct ViewingDiaryEditorView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedEntry: ViewingDiaryEntry?
    let target: ViewingDiaryTarget

    var body: some View {
        ZStack {
            AmbientBackdrop()

            if let title {
                if model.isDiaryTargetWatched(target) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                            ViewingDiaryTargetHeader(title: title, target: target)
                            ratingSection
                            noteLink(title: title)

                            if target.scope != .season {
                                watchHistory(title: title)
                            }
                        }
                        .padding(.horizontal, AppTheme.horizontalPadding)
                        .padding(.top, 12)
                        .padding(.bottom, 36)
                    }
                } else {
                    ContentUnavailableView(
                        "Diary locked",
                        systemImage: "eye.slash.fill",
                        description: Text("Mark this episode watched before adding a rating, note, or rewatch.")
                    )
                }
            } else {
                ContentUnavailableView("Title unavailable", systemImage: "questionmark.folder")
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedEntry) { entry in
            ViewingDiaryWatchDateEditor(entry: entry)
        }
    }

    private var title: MediaTitle? {
        model.mediaTitle(withID: target.titleID)
    }

    private var navigationTitle: String {
        switch target {
        case .title: "Viewing details"
        case .season(_, _, let seasonNumber): "Season \(seasonNumber) diary"
        case .episode(_, _, let seasonNumber, _, let episodeNumber):
            "S\(seasonNumber) E\(episodeNumber) diary"
        }
    }

    private var ratingSection: some View {
        TrackingRatingSection(rating: model.diaryRating(for: target)) { rating in
            model.updateDiaryRating(rating, for: target)
        }
    }

    private func noteLink(title: MediaTitle) -> some View {
        NavigationLink {
            ViewingDiaryNoteEditor(
                target: target,
                titleName: title.title,
                initialText: model.diaryNote(for: target) ?? ""
            )
        } label: {
            GlassSurface(cornerRadius: AppTheme.compactRadius) {
                HStack(spacing: 12) {
                    Image(systemName: model.diaryNote(for: target) == nil ? "note.text.badge.plus" : "note.text")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Private note")
                            .font(.headline)
                        Text(model.diaryNote(for: target) ?? "Add something only you can see")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .padding(14)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens a private diary note about \(title.title)")
    }

    private func watchHistory(title: MediaTitle) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(
                title: "Watch history",
                subtitle: "Each watch keeps its own editable date"
            )

            let entries = model.diaryEntries(for: target)
            if entries.isEmpty {
                Button("Add watch date", systemImage: "calendar.badge.plus") {
                    model.recordDiaryWatch(for: target, watchedAt: .now, isRewatch: false)
                }
                .frame(maxWidth: .infinity)
                .controlSize(.large)
                .adaptiveGlassButton(prominent: true)
            } else {
                GlassSurface(cornerRadius: AppTheme.compactRadius) {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in
                            Button {
                                selectedEntry = entry
                            } label: {
                                ViewingDiaryWatchRow(entry: entry)
                            }
                            .buttonStyle(.plain)

                            if entry.id != entries.last?.id {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                }
            }

            Button("Record a rewatch", systemImage: "arrow.counterclockwise.circle") {
                recordRewatch(title: title)
            }
            .frame(maxWidth: .infinity)
            .controlSize(.large)
            .adaptiveGlassButton()
        }
    }

    private func recordRewatch(title: MediaTitle) {
        switch target {
        case .title:
            model.recordRewatch(title.id)
        case .season:
            break
        case .episode(let titleID, _, let seasonNumber, let episodeID, _):
            model.recordEpisodeRewatch(
                titleID: titleID,
                seasonNumber: seasonNumber,
                episodeID: episodeID
            )
        }
    }
}

private struct ViewingDiaryTargetHeader: View {
    let title: MediaTitle
    let target: ViewingDiaryTarget

    var body: some View {
        GlassSurface(tint: Color(hex: title.palette.primaryHex)) {
            HStack(spacing: 14) {
                PosterArtwork(title: title, cornerRadius: 10)
                    .frame(width: 70, height: 102)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 7) {
                    Text(title.title)
                        .font(.title2.weight(.black))
                        .lineLimit(2)
                    Label(scopeLabel, systemImage: scopeSymbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Label("Private to this device", systemImage: "lock.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.indigo)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
        }
        .accessibilityElement(children: .combine)
    }

    private var scopeLabel: String {
        switch target {
        case .title: title.kind.label
        case .season(_, _, let seasonNumber): "Season \(seasonNumber)"
        case .episode(_, _, let seasonNumber, _, let episodeNumber):
            "Season \(seasonNumber), episode \(episodeNumber)"
        }
    }

    private var scopeSymbol: String {
        switch target.scope {
        case .title: title.kind.symbol
        case .season: "rectangle.stack.fill"
        case .episode: "play.rectangle.fill"
        }
    }
}

private struct ViewingDiaryWatchRow: View {
    let entry: ViewingDiaryEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.isRewatch ? "arrow.clockwise" : "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(entry.isRewatch ? .orange : .green)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.isRewatch ? "Rewatch" : "First watch")
                    .font(.headline)
                Text(dateLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "calendar.badge.clock")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(16)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Edits or removes this watch date")
    }

    private var dateLabel: String {
        entry.watchedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Date removed"
    }
}

private struct ViewingDiaryWatchDateEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let entry: ViewingDiaryEntry
    @State private var includesDate: Bool
    @State private var date: Date

    init(entry: ViewingDiaryEntry) {
        self.entry = entry
        _includesDate = State(initialValue: entry.watchedAt != nil)
        _date = State(initialValue: entry.watchedAt ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Include watch date", isOn: $includesDate)
                    if includesDate {
                        DatePicker(
                            "Watched",
                            selection: $date,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                } footer: {
                    Text("Removing the date keeps the episode or movie marked watched and preserves its private rating and note.")
                }
            }
            .navigationTitle(entry.isRewatch ? "Edit rewatch" : "Edit watch date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.updateDiaryWatchDate(includesDate ? date : nil, entryID: entry.id)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ViewingDiaryNoteEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let target: ViewingDiaryTarget
    let titleName: String
    @State private var text: String

    init(target: ViewingDiaryTarget, titleName: String, initialText: String) {
        self.target = target
        self.titleName = titleName
        _text = State(initialValue: initialText)
    }

    var body: some View {
        ZStack {
            AmbientBackdrop()

            VStack(alignment: .leading, spacing: 12) {
                Text("Only you can see this diary note.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextEditor(text: $text)
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityLabel("Private diary note about \(titleName)")

                Spacer()
            }
            .padding(AppTheme.horizontalPadding)
        }
        .navigationTitle("Private note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    model.updateDiaryNote(text, for: target)
                    dismiss()
                }
            }
        }
    }
}
