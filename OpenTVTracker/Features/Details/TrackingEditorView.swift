import SwiftUI

struct TrackingEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let title: MediaTitle
    @State private var state: WatchState
    @State private var rating: Double
    @State private var hasRating: Bool
    @State private var notes: String
    @State private var season: Int
    @State private var episode: Int
    @State private var totalEpisodes: Int

    init(title: MediaTitle) {
        self.title = title
        _state = State(initialValue: title.state)
        _rating = State(initialValue: title.userRating ?? 7)
        _hasRating = State(initialValue: title.userRating != nil)
        _notes = State(initialValue: title.notes ?? "")
        _season = State(initialValue: title.progress?.season ?? 1)
        _episode = State(initialValue: title.progress?.episode ?? 0)
        _totalEpisodes = State(initialValue: title.progress?.totalEpisodes ?? 1)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Status") {
                    Picker("Watch status", selection: $state) {
                        ForEach(WatchState.allCases, id: \.self) { state in
                            Text(state.label).tag(state)
                        }
                    }
                }

                if title.kind == .series {
                    Section("Episode progress") {
                        Stepper("Season \(season)", value: $season, in: 1...99)
                        Stepper("Episode \(episode)", value: $episode, in: 0...max(totalEpisodes, 1))
                        Stepper("\(totalEpisodes) episodes this season", value: $totalEpisodes, in: max(episode, 1)...999)
                    }
                }

                Section("Your rating") {
                    Toggle("Add a rating", isOn: $hasRating)
                    if hasRating {
                        Slider(value: $rating, in: 0...10, step: 0.5) {
                            Text("Rating")
                        } minimumValueLabel: {
                            Text("0")
                        } maximumValueLabel: {
                            Text("10")
                        }
                        LabeledContent("Rating", value: rating.formatted(.number.precision(.fractionLength(1))))
                    }
                }

                Section("Private notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 110)
                        .accessibilityLabel("Notes about \(title.title)")
                }

                if title.state == .completed {
                    Section {
                        Button("Record another rewatch", systemImage: "arrow.counterclockwise.circle") {
                            model.recordRewatch(title.id)
                        }
                    } footer: {
                        Text("Rewatched \(title.completedRewatches) times.")
                    }
                }
            }
            .navigationTitle("Track \(title.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
    }

    private func save() {
        model.setWatchState(state, for: title.id)
        model.setUserRating(hasRating ? rating : nil, for: title.id)
        model.updateNotes(notes, for: title.id)
        if title.kind == .series {
            let progress = EpisodeProgress(
                season: season,
                episode: episode,
                totalEpisodes: totalEpisodes
            )
            if progress != title.progress {
                model.correctProgress(progress, for: title.id)
            }
        }
        dismiss()
    }
}

#Preview {
    TrackingEditorView(title: LibrarySnapshot.sample.titles[0])
        .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
}
