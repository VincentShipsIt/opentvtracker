import SwiftUI

enum DiscoverSheet: Identifiable {
    case assistant
    case categories
    case services
    case aiRanking
    case trailer(TrailerPresentation)

    var id: String {
        switch self {
        case .assistant: "assistant"
        case .categories: "categories"
        case .services: "services"
        case .aiRanking: "ai-ranking"
        case .trailer(let trailer): "trailer-\(trailer.id)"
        }
    }
}

struct AIRankingSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(
                        "Optional AI reranking",
                        isOn: Binding(
                            get: { model.allowsAIReranking },
                            set: { enabled in model.setAIRerankingEnabled(enabled) }
                        )
                    )
                } footer: {
                    Text("Off by default. Deterministic recommendations always remain available.")
                }

                Section("Exact payload preview") {
                    LabeledContent("Candidate", value: "TMDB catalog ID")
                    LabeledContent("Signals", value: "local score, mood, max runtime")
                    LabeledContent("Never sent", value: "notes, names, watch events")
                }

                Section("Failure behavior") {
                    Text("A 2.5-second timeout, quota error, invalid response, or unavailable provider silently falls back to the reproducible on-device ranking.")
                }
            }
            .navigationTitle("AI discovery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct ServiceManagerView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            StreamingServicesSettingsView()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct StreamingServicesSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section {
                ForEach(StreamingProvider.supportedSubscriptions) { provider in
                    Button {
                        model.toggleProvider(provider.id)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: provider.symbol)
                                .frame(width: 38, height: 38)
                                .background(provider.brandHex.map { Color(hex: $0) } ?? .accentColor, in: Circle())
                                .foregroundStyle(.white)
                            Text(provider.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: model.isProviderSelected(provider.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(model.isProviderSelected(provider.id) ? Color.accentColor : Color.secondary)
                        }
                    }
                }
            } header: {
                Text("I subscribe to")
            } footer: {
                Text("Discover and search only include titles available on at least one selected service.")
            }

            Section {
                Text("Availability is refreshed for your selected streaming region through TMDB's JustWatch-backed provider data.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Streaming services")
        .navigationBarTitleDisplayMode(.inline)
    }
}
