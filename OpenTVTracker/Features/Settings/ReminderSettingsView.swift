import SwiftUI

struct ReminderSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Episode and release reminders",
                    isOn: Binding(
                        get: { model.reminderSettings.isEnabled },
                        set: { enabled in
                            Task { await model.setRemindersEnabled(enabled) }
                        }
                    )
                )

                Toggle(
                    "Automatically include tracked titles",
                    isOn: Binding(
                        get: { model.reminderSettings.automaticallyRemindTrackedTitles },
                        set: { enabled in
                            Task { await model.setAutomaticTrackedTitleRemindersEnabled(enabled) }
                        }
                    )
                )
                .disabled(!model.reminderSettings.isEnabled)

                Picker(
                    "Default lead time",
                    selection: Binding(
                        get: { model.reminderSettings.defaultLeadTime },
                        set: { model.setDefaultReminderLeadTime($0) }
                    )
                ) {
                    ForEach(ReminderLeadTime.allCases) { leadTime in
                        Text(leadTime.label).tag(leadTime)
                    }
                }
                .disabled(!model.reminderSettings.isEnabled)

                Toggle(
                    "Selected-provider releases",
                    isOn: Binding(
                        get: { model.reminderSettings.providerAvailabilityEnabled },
                        set: { model.setProviderAvailabilityRemindersEnabled($0) }
                    )
                )
                .disabled(!model.reminderSettings.isEnabled)
            } header: {
                Text("Notifications")
            } footer: {
                Text("Permission is requested only when you turn on a reminder. Automatic reminders include tracked titles except muted per-show overrides.")
            }

            if !reminderTitles.isEmpty {
                Section {
                    ForEach(reminderTitles) { title in
                        TitleReminderSettingsRow(title: title)
                    }
                } header: {
                    Text("Per-show overrides")
                } footer: {
                    Text("Per-show reminders can stay enabled without automatically opting in the rest of your library.")
                }
            }

            Section {
                LabeledContent("Notification access", value: authorizationLabel)
                LabeledContent(
                    "Background refresh",
                    value: model.reminderCapability.backgroundRefreshAvailable ? "Available" : "Unavailable"
                )
            } header: {
                Text("Delivery")
            } footer: {
                if model.reminderCapability.backgroundRefreshAvailable {
                    Text("OpenTV refreshes schedules when catalog and tracking data change.")
                } else {
                    Text("Existing local reminders still fire. OpenTV refreshes future dates the next time you open the app.")
                }
            }

            if let reminderError = model.reminderError {
                Section {
                    Label(reminderError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Text("Home Screen and Lock Screen widgets use a minimal shared snapshot containing only title names, dates, and queue labels. Notes, ratings, and partner activity are never copied into the widget container.")
            } header: {
                Text("Widgets & privacy")
            }
        }
        .navigationTitle("Reminders & widgets")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.refreshReminderCapability()
        }
    }

    private var reminderTitles: [MediaTitle] {
        model.titles
            .filter { title in
                title.state != .completed
                    && (title.kind == .series || title.isOnPersonalWatchlist)
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private var authorizationLabel: String {
        switch model.reminderCapability.authorization {
        case .notDetermined: "Not requested"
        case .denied: "Disabled in Settings"
        case .authorized: "Allowed"
        case .provisional: "Delivered quietly"
        case .ephemeral: "Temporarily allowed"
        }
    }
}

private struct TitleReminderSettingsRow: View {
    @Environment(AppModel.self) private var model
    let title: MediaTitle

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(
                title.title,
                isOn: Binding(
                    get: { model.isReminderEnabled(for: title.id) },
                    set: { enabled in
                        if enabled {
                            Task {
                                await model.enableReminder(
                                    for: title.id,
                                    leadTime: model.reminderLeadTime(for: title.id)
                                )
                            }
                        } else {
                            model.disableReminder(for: title.id)
                        }
                    }
                )
            )

            if model.isReminderEnabled(for: title.id) {
                Picker(
                    "Lead time",
                    selection: Binding(
                        get: { model.reminderLeadTime(for: title.id) },
                        set: { leadTime in
                            Task { await model.enableReminder(for: title.id, leadTime: leadTime) }
                        }
                    )
                ) {
                    ForEach(ReminderLeadTime.allCases) { leadTime in
                        Text(leadTime.label).tag(leadTime)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }
}

struct TitleReminderEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let title: MediaTitle
    @State private var leadTime: ReminderLeadTime
    @State private var isSaving = false

    init(title: MediaTitle, leadTime: ReminderLeadTime) {
        self.title = title
        _leadTime = State(initialValue: leadTime)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Notify me", selection: $leadTime) {
                        ForEach(ReminderLeadTime.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                } footer: {
                    Text("The notification names \(title.title), but hides episode titles and story details.")
                }

                Section {
                    Button("Enable reminder", systemImage: "bell.fill") {
                        isSaving = true
                        Task {
                            await model.enableReminder(for: title.id, leadTime: leadTime)
                            isSaving = false
                            if model.isReminderEnabled(for: title.id) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(isSaving)

                    if model.isReminderEnabled(for: title.id) {
                        Button("Disable for this title", systemImage: "bell.slash", role: .destructive) {
                            model.disableReminder(for: title.id)
                            dismiss()
                        }
                    }
                }

                if let reminderError = model.reminderError {
                    Section {
                        Label(reminderError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ReminderSettingsView()
            .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
    }
}
