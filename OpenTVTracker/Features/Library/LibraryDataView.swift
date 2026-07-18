import SwiftUI
import UniformTypeIdentifiers

struct LibraryDataView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage(BackupHealth.lastSuccessfulExportTimestampKey)
    private var lastSuccessfulBackupTimestamp = 0.0
    @State private var exportDocument: LibraryExportDocument?
    @State private var exportContentType: UTType = .json
    @State private var exportFilename = "OpenTV-library"
    @State private var pendingExportKind: LibraryExportKind?
    @State private var showsExporter = false
    @State private var showsImporter = false
    @State private var showsConversationDeletionConfirmation = false
    @State private var isImporting = false
    @State private var importPreview: LibraryImportPreview?
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Backup health") {
                    Label(backupHealth.label, systemImage: backupHealth.systemImage)
                    Text(backupHealth.reminder)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Portable backup") {
                    Button("Export complete JSON", systemImage: "square.and.arrow.up") {
                        prepareExport(.json)
                    }
                    Button("Export titles CSV", systemImage: "tablecells") {
                        prepareExport(.titlesCSV)
                    }
                    Button("Export watch events CSV", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90") {
                        prepareExport(.eventsCSV)
                    }
                    Button("Export private conversations CSV", systemImage: "bubble.left.and.bubble.right") {
                        prepareExport(.conversationsCSV)
                    }
                }

                Section {
                    Button("Import OpenTV or TV Time", systemImage: "square.and.arrow.down") {
                        showsImporter = true
                    }
                    .disabled(isImporting)

                    if isImporting {
                        ProgressView("Reading your TV Time history…")
                    }
                } footer: {
                    Text("Choose an OpenTV JSON/CSV file or the ZIP from TV Time's data export. OpenTV previews every import before changing your library.")
                }

                if let importPreview {
                    Section("Import preview") {
                        LabeledContent("Source", value: importPreview.sourceName)
                        LabeledContent("Matched", value: String(importPreview.matchedCount))
                        LabeledContent("New", value: String(importPreview.addedCount))
                        if importPreview.watchedEpisodeCount > 0 {
                            LabeledContent("Watched episodes", value: String(importPreview.watchedEpisodeCount))
                        }
                        if importPreview.watchEventCount > 0 {
                            LabeledContent("Dated watches", value: String(importPreview.watchEventCount))
                        }
                        LabeledContent("Duplicates", value: String(importPreview.duplicateCount))
                        LabeledContent("Skipped", value: String(importPreview.skippedCount))

                        if let importNotice = importPreview.importNotice {
                            Text(importNotice)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Button("Apply import", systemImage: "checkmark.circle.fill") {
                            model.replaceLibrary(with: importPreview.snapshot)
                            self.importPreview = nil
                            statusMessage = "Import applied."
                        }
                    }
                }

                if let statusMessage {
                    Section {
                        Label(statusMessage, systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                }

                if model.sharedSpace.isCurrentUserShareOwner == true,
                   hasPrivateConversationData {
                    Section {
                        Button(
                            "Delete private conversation data",
                            systemImage: "bubble.left.and.exclamationmark.bubble.right",
                            role: .destructive
                        ) {
                            showsConversationDeletionConfirmation = true
                        }
                    } footer: {
                        Text("The shared-space owner can remove locally retained episode notes and reactions. Deletion syncs to invited members and does not remove watch history.")
                    }
                }
            }
            .navigationTitle("Your data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileExporter(
                isPresented: $showsExporter,
                document: exportDocument,
                contentType: exportContentType,
                defaultFilename: exportFilename
            ) { result in
                defer { pendingExportKind = nil }
                switch result {
                case .success:
                    if pendingExportKind?.completesBackup == true {
                        lastSuccessfulBackupTimestamp = Date.now.timeIntervalSince1970
                        statusMessage = "Complete backup exported."
                    } else {
                        statusMessage = "CSV exported. Complete JSON is the restorable backup."
                    }
                case .failure(let error):
                    if (error as? CocoaError)?.code != .userCancelled {
                        statusMessage = error.localizedDescription
                    }
                }
            }
            .fileImporter(
                isPresented: $showsImporter,
                allowedContentTypes: [.zip, .json, .commaSeparatedText]
            ) { result in
                importFile(result)
            }
            .confirmationDialog(
                "Delete private conversation data?",
                isPresented: $showsConversationDeletionConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete conversations", role: .destructive) {
                    Task {
                        await model.deletePrivateConversationData()
                        statusMessage = "Private conversation data deleted."
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes all episode notes and reactions from the private shared space on the next sync. Watch history stays intact.")
            }
        }
    }

    private func prepareExport(_ kind: LibraryExportKind) {
        do {
            let data: Data
            switch kind {
            case .json:
                data = try LibraryTransferService.exportJSON(model.snapshot)
                exportContentType = .json
                exportFilename = "OpenTV-library.json"
            case .titlesCSV:
                data = LibraryTransferService.exportTitlesCSV(model.snapshot)
                exportContentType = .commaSeparatedText
                exportFilename = "OpenTV-titles.csv"
            case .eventsCSV:
                data = LibraryTransferService.exportWatchEventsCSV(model.snapshot)
                exportContentType = .commaSeparatedText
                exportFilename = "OpenTV-watch-events.csv"
            case .conversationsCSV:
                data = LibraryTransferService.exportPrivateConversationsCSV(model.snapshot)
                exportContentType = .commaSeparatedText
                exportFilename = "OpenTV-private-conversations.csv"
            }
            exportDocument = LibraryExportDocument(data: data)
            pendingExportKind = kind
            showsExporter = true
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func importFile(_ result: Result<URL, any Error>) {
        do {
            let url = try result.get()
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess { url.stopAccessingSecurityScopedResource() }
            }
            let data = try Data(contentsOf: url)
            if TVTimeImportService.isZIPArchive(data) {
                isImporting = true
                Task {
                    defer { isImporting = false }
                    do {
                        importPreview = try await TVTimeImportService.previewImport(
                            data,
                            into: model.snapshot,
                            catalog: model.catalogService,
                            region: model.streamingRegion
                        )
                        statusMessage = nil
                    } catch {
                        importPreview = nil
                        statusMessage = error.localizedDescription
                    }
                }
            } else {
                importPreview = try LibraryTransferService.previewImport(data, into: model.snapshot)
                statusMessage = nil
            }
        } catch {
            importPreview = nil
            statusMessage = error.localizedDescription
        }
    }

    private var backupHealth: BackupHealthState {
        BackupHealth.state(
            lastSuccessfulExportAt: BackupHealth.lastSuccessfulExportAt(
                from: lastSuccessfulBackupTimestamp
            )
        )
    }

    private var hasPrivateConversationData: Bool {
        model.sharedSpace.notes?.isEmpty == false
            || model.sharedSpace.reactions?.isEmpty == false
    }
}

enum LibraryExportKind: Equatable {
    case json
    case titlesCSV
    case eventsCSV
    case conversationsCSV

    var completesBackup: Bool {
        self == .json
    }
}

struct LibraryExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json, .commaSeparatedText]
    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

#Preview {
    LibraryDataView()
        .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
}
