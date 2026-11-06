import SwiftUI

/// The front door: say what you feel like watching, or vote on today's three picks.
/// Votes are shared with a connected partner, so a suggestion can be settled together.
struct ChatHomeView: View {
    @Environment(AppModel.self) private var model
    @State private var conversation = DiscoveryConversation()
    @State private var starterCards: [DiscoveryAssistantMatch] = []
    @State private var prompt = ""
    @State private var voice = VoiceSearchTranscriber()
    @FocusState private var isPromptFocused: Bool

    private static let bottomAnchor = "chat.bottom-anchor"

    private let examples = [
        "A funny show under 60 minutes",
        "A top-rated movie for date night",
        "Something new we would both like"
    ]

    private var partnerName: String? {
        model.sharedSpace.members.first { !$0.isCurrentUser }?.name
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackdrop()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            if conversation.turns.isEmpty {
                                starterSection
                            }
                            ChatPartnerVotesSection(
                                board: model.suggestionVoteBoard,
                                partnerName: partnerName,
                                titleLookup: model.mediaTitle(withID:),
                                onVote: vote
                            )
                            ForEach(conversation.turns) { turn in
                                ChatTurnView(
                                    turn: turn,
                                    board: model.suggestionVoteBoard,
                                    partnerName: partnerName,
                                    onVote: vote
                                )
                            }
                            Color.clear
                                .frame(height: 1)
                                .id(Self.bottomAnchor)
                        }
                        .padding(.horizontal, AppTheme.horizontalPadding)
                        .padding(.top, 16)
                        .padding(.bottom, 28)
                    }
                    .accessibilityIdentifier("chat.scroll")
                    .onChange(of: conversation.turns.count) {
                        withAnimation { proxy.scrollTo(Self.bottomAnchor, anchor: .bottom) }
                    }
                }
            }
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if !conversation.turns.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("New chat", systemImage: "square.and.pencil") {
                            conversation.reset()
                        }
                        .accessibilityIdentifier("chat.new")
                    }
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
                    onToggleVoice: { Task { await voice.toggleRecording() } }
                )
            }
            .onChange(of: voice.transcript) {
                prompt = voice.transcript
            }
            .onDisappear {
                voice.stopRecording()
            }
            .task(id: model.discoverableTitles.count) {
                starterCards = model.dailySuggestionCards
            }
        }
    }

    private var starterSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(starterCards.isEmpty ? "What should we watch?" : "Three picks for today")
                    .font(.title2.weight(.bold))
                Text(starterSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            ForEach(starterCards) { match in
                SuggestionCard(
                    match: match,
                    board: model.suggestionVoteBoard,
                    partnerName: partnerName,
                    onVote: { vote($0, for: match.title.id) }
                )
            }

            HorizontalShelf(showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(examples, id: \.self) { example in
                        Button(example) { ask(example) }
                            .adaptiveGlassButton()
                    }
                }
            }
            .accessibilityLabel("Example requests")
        }
    }

    private var starterSubtitle: String {
        if let partnerName {
            "Vote yes, maybe or pass. \(partnerName) sees your votes, and you will see when you both say yes."
        } else {
            "Vote yes, maybe or pass, or tell me a mood, genre or runtime."
        }
    }

    private func vote(_ choice: SuggestionVoteChoice, for titleID: MediaTitle.ID) {
        model.castSuggestionVote(choice, for: titleID)
    }

    private func submit() {
        let request = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return }
        voice.stopRecording()
        ask(request)
    }

    private func ask(_ request: String) {
        var seenIDs: Set<MediaTitle.ID> = []
        let candidates = (model.discoverableTitles + model.catalogSearchResults)
            .filter { seenIDs.insert($0.id).inserted }
        conversation.ask(
            request,
            titles: candidates,
            selectedProviderIDs: model.selectedProviderIDs,
            tasteProfiles: model.sharedSpace.tasteProfiles ?? []
        )
        prompt = ""
        isPromptFocused = false
    }
}

#Preview {
    ChatHomeView()
        .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
        .environment(\.allowsRemoteArtwork, false)
}
