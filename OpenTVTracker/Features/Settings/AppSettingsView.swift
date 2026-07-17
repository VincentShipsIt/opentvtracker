import SwiftUI

struct AppSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var showsCredits = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        StreamingRegionPickerView()
                    } label: {
                        LabeledContent("Streaming region") {
                            Text("\(model.streamingRegion.flag) \(model.streamingRegion.displayName())")
                        }
                    }

                    NavigationLink {
                        StreamingServicesSettingsView()
                    } label: {
                        LabeledContent("Subscriptions", value: subscriptionSummary)
                    }
                } header: {
                    Text("Availability")
                } footer: {
                    Text("Automatic follows this iPhone's Region setting. OpenTV never requests your GPS location.")
                }

                Section {
                    Toggle(
                        "Optional AI reranking",
                        isOn: Binding(
                            get: { model.allowsAIReranking },
                            set: { model.setAIRerankingEnabled($0) }
                        )
                    )
                } header: {
                    Text("Discovery")
                } footer: {
                    Text("Off by default. Deterministic on-device recommendations always remain available.")
                }

                Section {
                    NavigationLink {
                        TraktSettingsView()
                    } label: {
                        LabeledContent("Trakt", value: model.isTraktAuthorized ? "Connected" : "Optional")
                    }
                } header: {
                    Text("Integrations")
                } footer: {
                    Text("OpenTV remains fully functional offline and without a Trakt account.")
                }

                Section {
                    Button("Credits & privacy", systemImage: "hand.raised.fill") {
                        showsCredits = true
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showsCredits) {
                CreditsView()
            }
        }
    }

    private var subscriptionSummary: String {
        let count = model.selectedProviders.count
        return count == 1 ? "1 service" : "\(count) services"
    }
}

private struct StreamingRegionPickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        List {
            Section {
                Button {
                    select(nil)
                } label: {
                    RegionSelectionRow(
                        title: "Automatic",
                        subtitle: "\(StreamingRegion.deviceDefault().flag) \(StreamingRegion.deviceDefault().displayName())",
                        isSelected: model.streamingRegionOverride == nil
                    )
                }
            } footer: {
                Text("Uses Settings → General → Language & Region. No location permission is needed.")
            }

            Section("Countries and regions") {
                ForEach(filteredRegions) { region in
                    Button {
                        select(region)
                    } label: {
                        RegionSelectionRow(
                            title: "\(region.flag)  \(region.displayName())",
                            subtitle: region.code,
                            isSelected: model.streamingRegionOverride == region
                        )
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .navigationTitle("Streaming region")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Country or code")
    }

    private var filteredRegions: [StreamingRegion] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return StreamingRegion.available }
        return StreamingRegion.available.filter { region in
            region.code.localizedStandardContains(query)
                || region.displayName().localizedStandardContains(query)
        }
    }

    private func select(_ region: StreamingRegion?) {
        model.setStreamingRegionOverride(region)
        dismiss()
    }
}

private struct RegionSelectionRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

#Preview {
    AppSettingsView()
        .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
}
