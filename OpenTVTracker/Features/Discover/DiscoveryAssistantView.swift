import SwiftUI

struct DiscoveryAssistantView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var prompt = ""
    @State private var response: DiscoveryAssistantResponse?
    @State private var voice = VoiceSearchTranscriber()
    @FocusState private var isPromptFocused: Bool

    private let suggestions = [
        "A funny show under 60 minutes",
        "A top-rated movie for date night",
        "A tense sci-fi series",
        "Something new we would both like"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackdrop()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        AssistantScopeNotice()
                        AssistantPromptSuggestions(suggestions: suggestions, onSelect: useSuggestion)

                        if let response {
                            AssistantResults(response: response)
                        } else {
                            ContentUnavailableView(
                                "Tell me what sounds good",
                                systemImage: "sparkles.bubble.fill",
                                description: Text("Mention a mood, genre, runtime, rating, movie or show. I only pick from services you selected.")
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                        }
                    }
                    .padding(.horizontal, AppTheme.horizontalPadding)
                    .padding(.top, 16)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Ask OpenTV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(for: MediaTitle.self) { title in
                MediaDetailView(titleID: title.id)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                AssistantComposer(
                    prompt: $prompt,
                    isPromptFocused: $isPromptFocused,
                    voice: voice,
                    onSubmit: submit,
                    onToggleVoice: toggleVoice
                )
            }
            .onChange(of: voice.transcript) {
                prompt = voice.transcript
            }
            .onDisappear {
                voice.stopRecording()
            }
        }
    }

    private func useSuggestion(_ suggestion: String) {
        prompt = suggestion
        response = model.askDiscoveryAssistant(suggestion)
        isPromptFocused = false
    }

    private func submit() {
        let request = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return }
        voice.stopRecording()
        response = model.askDiscoveryAssistant(request)
        isPromptFocused = false
    }

    private func toggleVoice() {
        Task { await voice.toggleRecording() }
    }
}

private struct AssistantScopeNotice: View {
    var body: some View {
        GlassSurface(cornerRadius: AppTheme.compactRadius, tint: .indigo) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Your services only", systemImage: "play.tv.fill")
                    .font(.headline)
                Text("Ask by mood, genre, runtime, or rating. OpenTV only suggests titles available on streaming services you selected.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AssistantPromptSuggestions: View {
    let suggestions: [String]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Try a request")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Label("Swipe for more", systemImage: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button(suggestion) { onSelect(suggestion) }
                            .adaptiveGlassButton()
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.visible)
            .accessibilityLabel("Suggested requests")
        }
    }
}

private struct AssistantResults: View {
    let response: DiscoveryAssistantResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(response.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if response.matches.isEmpty {
                ContentUnavailableView(
                    "No exact matches",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text(response.summary)
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                ForEach(response.matches) { match in
                    NavigationLink(value: match.title) {
                        AssistantResultCard(match: match)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct AssistantResultCard: View {
    let match: DiscoveryAssistantMatch

    var body: some View {
        GlassSurface(cornerRadius: AppTheme.compactRadius, tint: Color(hex: match.title.palette.primaryHex)) {
            HStack(spacing: 14) {
                PosterArtwork(title: match.title, cornerRadius: 10)
                    .frame(width: 82, height: 120)

                VStack(alignment: .leading, spacing: 7) {
                    Text(match.title.title)
                        .font(.title3.weight(.bold))
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        RatingLabel(rating: match.title.rating)
                        Text("\(match.title.runtimeMinutes) min")
                        if let provider = match.title.providers.first {
                            Text(provider.name)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                    Text(match.reason)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
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
        .accessibilityHint("Opens details")
    }
}

private struct AssistantComposer: View {
    @Binding var prompt: String
    var isPromptFocused: FocusState<Bool>.Binding
    let voice: VoiceSearchTranscriber
    let onSubmit: () -> Void
    let onToggleVoice: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if let errorMessage = voice.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            GlassSurface(cornerRadius: 22) {
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("What should we watch?", text: $prompt, axis: .vertical)
                        .focused(isPromptFocused)
                        .lineLimit(1...4)
                        .submitLabel(.search)
                        .onSubmit(onSubmit)

                    Button(
                        voice.isRecording ? "Stop listening" : "Use voice",
                        systemImage: voice.isRecording ? "stop.fill" : "mic.fill",
                        action: onToggleVoice
                    )
                    .labelStyle(.iconOnly)
                    .foregroundStyle(voice.isRecording ? Color.red : Color.accentColor)
                    .frame(width: 36, height: 36)
                    .accessibilityValue(voice.isRecording ? "Listening" : "Not listening")

                    Button("Find picks", systemImage: "arrow.up", action: onSubmit)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.circle)
                        .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }

            Text(voice.isRecording ? "Listening… tap stop when finished" : "Voice uses on-device recognition when your iPhone supports it.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, AppTheme.horizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .glassEffect(.regular, in: .rect)
    }
}

#Preview {
    DiscoveryAssistantView()
        .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
        .environment(\.allowsRemoteArtwork, false)
}
