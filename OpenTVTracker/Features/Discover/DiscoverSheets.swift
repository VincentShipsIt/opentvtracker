import SwiftUI

enum DiscoverSheet: Identifiable {
    case prompt
    case services
    case trailer(TrailerPresentation)

    var id: String {
        switch self {
        case .prompt: "prompt"
        case .services: "services"
        case .trailer(let trailer): "trailer-\(trailer.id)"
        }
    }
}

struct ServiceManagerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
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
                    Text("Availability will be refreshed by region through TMDB's JustWatch-backed provider data. Provider deep links remain on the source page.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Streaming services")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct DiscoveryPromptView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var maximumRuntime = 60.0

    var body: some View {
        NavigationStack {
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
                            LabeledContent(title.title, value: title.providers.first?.name ?? "Your services")
                        }
                    } else {
                        Text("No exact match yet. Widen the runtime, mood, or selected services.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Text("The current picker is deterministic. Optional AI reranking will use the same service, mood, and runtime constraints through the private server boundary.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
