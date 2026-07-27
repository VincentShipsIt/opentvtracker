import SwiftUI

struct AppSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @AppStorage(BackupHealth.lastSuccessfulExportTimestampKey)
    private var lastSuccessfulBackupTimestamp = 0.0
    @AppStorage(EpisodeSpoilerPolicy.hidesUnwatchedDetailsKey)
    private var hidesUnwatchedEpisodeDetails = false
    @State private var showsCredits = false
    @State private var showsDataTools = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(model.currentMember.name, systemImage: "person.crop.circle.fill")
                            .font(.headline)
                        Label("Personal history", systemImage: "lock.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.indigo)
                    }
                    .accessibilityElement(children: .combine)
                } header: {
                    Text("Profile")
                } footer: {
                    Text("Your viewing history stays private and is stored on this iPhone unless you explicitly share or export it.")
                }

                Section {
                    NavigationLink {
                        StreamingRegionPickerView()
                    } label: {
                        LabeledContent("Streaming region") {
                            Text(
                                "\(model.streamingRegion.flag) "
                                    + model.streamingRegion.displayName(locale: locale)
                            )
                        }
                    }

                    NavigationLink {
                        ContentLanguagePickerView()
                    } label: {
                        LabeledContent("Content language") {
                            Text(model.contentLanguage.displayName(locale: locale))
                        }
                    }

                    NavigationLink {
                        StreamingServicesSettingsView()
                    } label: {
                        LabeledContent("Subscriptions", value: subscriptionSummary)
                    }

                    NavigationLink {
                        ReminderSettingsView()
                    } label: {
                        LabeledContent(
                            "Reminders & widgets",
                            value: model.reminderSettings.isEnabled ? "On" : "Off"
                        )
                    }
                } header: {
                    Text("Availability")
                } footer: {
                    Text("Region controls local availability. Content language controls default browsing. Automatic follows this iPhone's Language & Region settings; OpenTV never requests GPS location.")
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
                    Toggle("Hide details for unwatched episodes", isOn: $hidesUnwatchedEpisodeDetails)
                } header: {
                    Text("Spoilers")
                } footer: {
                    Text("Off by default. When on, episode stills, titles, and summaries stay hidden until you mark the episode watched. This setting stays on this iPhone.")
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
                    Button {
                        showsDataTools = true
                    } label: {
                        // A plain row, laid out by hand. `LabeledContent`'s ViewBuilder
                        // slot gives its content the row's full width *and* an unbounded
                        // height, and a `Label` handed that grows to fill it — which is
                        // what turned one line of backup status into a row several hundred
                        // points tall next to the single-line Trakt row above.
                        HStack {
                            Text("Portable backup")
                            Spacer()
                            Label(backupHealth.label, systemImage: backupHealth.systemImage)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityHint("Opens import and export tools")
                } header: {
                    Text("Your data")
                } footer: {
                    Text(backupHealth.reminder)
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
            .sheet(isPresented: $showsDataTools) {
                LibraryDataView()
            }
        }
    }

    private var backupHealth: BackupHealthState {
        BackupHealth.state(
            lastSuccessfulExportAt: BackupHealth.lastSuccessfulExportAt(
                from: lastSuccessfulBackupTimestamp
            )
        )
    }

    private var subscriptionSummary: String {
        CountLabel.services(model.selectedProviders.count)
    }

}

private struct StreamingRegionPickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var searchText = ""

    var body: some View {
        List {
            Section {
                let automaticRegion = StreamingRegion.deviceDefault()
                Button {
                    select(nil)
                } label: {
                    RegionSelectionRow(
                        title: "Automatic",
                        subtitle: "\(automaticRegion.flag) \(automaticRegion.displayName(locale: locale)) · \(automaticRegion.code)",
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
                            title: "\(region.flag)  \(region.displayName(locale: locale))",
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
        let regions = StreamingRegion.available.sorted {
            $0.displayName(locale: locale)
                .localizedStandardCompare($1.displayName(locale: locale)) == .orderedAscending
        }
        guard !query.isEmpty else { return regions }
        return regions.filter { region in
            region.code.localizedStandardContains(query)
                || region.displayName(locale: locale).localizedStandardContains(query)
        }
    }

    private func select(_ region: StreamingRegion?) {
        model.setStreamingRegionOverride(region)
        dismiss()
    }
}

private struct ContentLanguagePickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var searchText = ""

    var body: some View {
        List {
            Section {
                let automaticLanguage = ContentLanguage.deviceDefault(locale: locale)
                Button {
                    select(nil)
                } label: {
                    RegionSelectionRow(
                        title: "Automatic",
                        subtitle: "\(automaticLanguage.displayName(locale: locale)) · \(automaticLanguage.code.uppercased())",
                        isSelected: model.contentLanguageOverride == nil
                    )
                }
            } footer: {
                Text("Uses this iPhone's preferred language. Search still finds titles in every language.")
            }

            Section("Languages") {
                ForEach(filteredLanguages) { language in
                    Button {
                        select(language)
                    } label: {
                        RegionSelectionRow(
                            title: language.displayName(locale: locale),
                            subtitle: language.code.uppercased(),
                            isSelected: model.contentLanguageOverride == language
                        )
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .navigationTitle("Content language")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Language or code")
    }

    private var filteredLanguages: [ContentLanguage] {
        let languages = ContentLanguage.available.sorted {
            $0.displayName(locale: locale)
                .localizedStandardCompare($1.displayName(locale: locale)) == .orderedAscending
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return languages }
        return languages.filter { language in
            language.code.localizedStandardContains(query)
                || language.displayName(locale: locale).localizedStandardContains(query)
        }
    }

    private func select(_ language: ContentLanguage?) {
        model.setContentLanguageOverride(language)
        dismiss()
    }
}

private struct RegionSelectionRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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
