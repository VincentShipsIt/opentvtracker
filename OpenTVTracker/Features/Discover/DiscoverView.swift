import SwiftUI

struct DiscoverView: View {
    @Environment(AppModel.self) private var model
    @State private var searchText = ""
    @State private var surpriseOffset = 0
    @State private var presentedPrompt: DiscoveryPrompt?

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackdrop()

                ScrollView {
                    LazyVStack(spacing: AppTheme.sectionSpacing) {
                        discoverySkill
                        moodPicker

                        if searchText.isEmpty {
                            recommendationResults
                        } else {
                            searchResults
                        }
                    }
                    .padding(.horizontal, AppTheme.horizontalPadding)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Discover")
            .searchable(text: $searchText, prompt: "Shows, movies, people")
            .navigationDestination(for: MediaTitle.self) { title in
                MediaDetailView(titleID: title.id)
            }
            .sheet(item: $presentedPrompt) { prompt in
                DiscoveryPromptView(prompt: prompt)
            }
        }
    }

    private var discoverySkill: some View {
        GlassSurface(tint: .indigo) {
            VStack(alignment: .leading, spacing: 14) {
                Label("Pick something for us", systemImage: "wand.and.stars")
                    .font(.title2.weight(.bold))
                Text("Turn mood, time, and both of your histories into a short list that explains itself.")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Choose tonight", systemImage: "sparkles") {
                        presentedPrompt = .tonight
                    }
                    .adaptiveGlassButton(prominent: true)

                    Button("Surprise me", systemImage: "dice") {
                        let count = max(model.recommendations.count, 1)
                        surpriseOffset = (surpriseOffset + 1) % count
                    }
                    .adaptiveGlassButton()
                }
            }
            .padding(18)
        }
        .padding(.top, 10)
    }

    private var moodPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "What fits?", subtitle: "The ranking updates without hiding why")
            ScrollView(.horizontal) {
                HStack(spacing: 9) {
                    ForEach(Mood.allCases) { mood in
                        Button {
                            model.selectedMood = mood
                        } label: {
                            Label(mood.label, systemImage: mood.symbol)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .tint(model.selectedMood == mood ? .accentColor : .secondary)
                        .accessibilityAddTraits(model.selectedMood == mood ? .isSelected : [])
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .sensoryFeedback(.selection, trigger: model.selectedMood)
        }
    }

    @ViewBuilder
    private var recommendationResults: some View {
        let recommendations = rotated(model.recommendations)
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(
                title: recommendations.isEmpty ? "No exact matches" : "Why these fit",
                subtitle: recommendations.isEmpty ? "Try a different mood" : "Built from your current library"
            )

            if recommendations.isEmpty {
                ContentUnavailableView.search(text: model.selectedMood.label)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ForEach(recommendations) { title in
                    NavigationLink(value: title) {
                        RecommendationRow(title: title)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "Results", subtitle: "Searching your local catalog preview")
            if filteredTitles.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ForEach(filteredTitles) { title in
                    NavigationLink(value: title) {
                        RecommendationRow(title: title)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var filteredTitles: [MediaTitle] {
        model.titles.filter { title in
            title.title.localizedStandardContains(searchText)
                || title.genres.contains(where: { $0.localizedStandardContains(searchText) })
        }
    }

    private func rotated(_ titles: [MediaTitle]) -> [MediaTitle] {
        guard !titles.isEmpty else { return [] }
        let offset = surpriseOffset % titles.count
        return Array(titles[offset...]) + Array(titles[..<offset])
    }
}

private struct RecommendationRow: View {
    let title: MediaTitle

    var body: some View {
        GlassSurface(cornerRadius: AppTheme.compactRadius, tint: Color(hex: title.palette.primaryHex)) {
            HStack(alignment: .top, spacing: 14) {
                PosterArtwork(title: title, cornerRadius: 12)
                    .frame(width: 84, height: 120)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(title.title)
                            .font(.headline)
                        Spacer()
                        RatingLabel(rating: title.rating)
                    }
                    Text("\(title.year) · \(title.runtimeMinutes) min · \(title.kind.label)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let reason = title.recommendationReason {
                        Label(reason, systemImage: "sparkles")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

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

private enum DiscoveryPrompt: String, Identifiable {
    case tonight

    var id: String { rawValue }
}

private struct DiscoveryPromptView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let prompt: DiscoveryPrompt
    @State private var maximumRuntime = 60.0

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackdrop()
                Form {
                    Section("Tonight") {
                        Picker("Mood", selection: moodBinding) {
                            ForEach(Mood.allCases) { mood in
                                Text(mood.label).tag(mood)
                            }
                        }

                        VStack(alignment: .leading) {
                            Text("Up to \(Int(maximumRuntime)) minutes")
                            Slider(value: $maximumRuntime, in: 25...150, step: 5)
                        }
                    }

                    Section("Best current fit") {
                        if let title = bestFit {
                            NavigationLink(value: title) {
                                LabeledContent(title.title, value: title.recommendationReason ?? "Matches your filters")
                            }
                        } else {
                            Text("No exact match yet. Widen the runtime or mood.")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section {
                        Text("The foundation uses deterministic matching. Optional AI reranking will use the same constraints through a privacy-preserving server boundary.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Choose tonight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(for: MediaTitle.self) { title in
                MediaDetailView(titleID: title.id)
            }
        }
    }

    private var moodBinding: Binding<Mood> {
        Binding(
            get: { model.selectedMood },
            set: { model.selectedMood = $0 }
        )
    }

    private var bestFit: MediaTitle? {
        model.recommendations.first(where: { $0.runtimeMinutes <= Int(maximumRuntime) })
    }
}

#Preview {
    DiscoverView()
        .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
}
