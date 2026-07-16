import SwiftUI
import UniformTypeIdentifiers

struct LibraryDataView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var exportDocument: LibraryExportDocument?
    @State private var exportContentType: UTType = .json
    @State private var exportFilename = "OpenTV-library"
    @State private var showsExporter = false
    @State private var showsImporter = false
    @State private var isImporting = false
    @State private var importPreview: LibraryImportPreview?
    @State private var importCoordinator: TVTimeImportCoordinator?
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            Form {
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

                if let importPreview = currentPreview {
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
                    }

                    if !importPreview.integrityCounts.isEmpty {
                        ImportIntegritySection(counts: importPreview.integrityCounts)
                    }

                    if !importPreview.warnings.isEmpty {
                        ImportWarningsSection(warnings: importPreview.warnings)
                    }

                    if let importCoordinator, !importPreview.resolutionIssues.isEmpty {
                        ImportResolutionSection(
                            issues: importPreview.resolutionIssues,
                            coordinator: importCoordinator
                        )
                    }

                    Section {
                        Button("Apply import and save rollback backup", systemImage: "checkmark.circle.fill") {
                            applyImport(importPreview)
                        }
                        .disabled(importCoordinator?.isRefreshing == true)
                    } footer: {
                        Text("OpenTV applies every resolved record, then immediately offers a complete pre-import JSON backup for rollback.")
                    }
                }

                if let statusMessage {
                    Section {
                        Label(statusMessage, systemImage: "info.circle")
                            .foregroundStyle(.secondary)
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
                if case .failure(let error) = result {
                    statusMessage = error.localizedDescription
                }
            }
            .fileImporter(
                isPresented: $showsImporter,
                allowedContentTypes: [.zip, .json, .commaSeparatedText]
            ) { result in
                importFile(result)
            }
        }
    }

    private var currentPreview: LibraryImportPreview? {
        importCoordinator?.preview ?? importPreview
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
            }
            exportDocument = LibraryExportDocument(data: data)
            showsExporter = true
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func importFile(_ result: Result<URL, any Error>) {
        isImporting = true
        importPreview = nil
        importCoordinator = nil
        statusMessage = nil

        Task {
            defer { isImporting = false }
            do {
                let url = try result.get()
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if hasAccess { url.stopAccessingSecurityScopedResource() }
                }
                let data = try await Task.detached(priority: .userInitiated) {
                    try Data(contentsOf: url, options: .mappedIfSafe)
                }.value
                let snapshot = model.snapshot

                if TVTimeImportService.isZIPArchive(data) {
                    let session = try await TVTimeImportService.prepareImport(
                        data,
                        into: snapshot,
                        catalog: model.catalogService,
                        region: model.streamingRegion
                    )
                    let coordinator = TVTimeImportCoordinator(session: session)
                    importCoordinator = coordinator
                    await coordinator.refresh()
                } else {
                    importPreview = try await Task.detached(priority: .userInitiated) {
                        try LibraryTransferService.previewImport(data, into: snapshot)
                    }.value
                }
            } catch {
                importPreview = nil
                importCoordinator = nil
                statusMessage = error.localizedDescription
            }
        }
    }

    private func applyImport(_ preview: LibraryImportPreview) {
        do {
            let backup = try LibraryTransferService.exportJSON(model.snapshot)
            model.replaceLibrary(with: preview.snapshot)
            importPreview = nil
            importCoordinator = nil
            exportDocument = LibraryExportDocument(data: backup)
            exportContentType = .json
            exportFilename = "OpenTV-pre-import-backup.json"
            statusMessage = "Import applied. Save this rollback backup somewhere you control."
            showsExporter = true
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}

private struct ImportIntegritySection: View {
    let counts: [ImportCountComparison]

    var body: some View {
        Section {
            ForEach(counts) { count in
                LabeledContent(count.category.label) {
                    Text("\(count.importedCount) of \(count.sourceCount)")
                        .foregroundStyle(
                            count.importedCount == count.sourceCount ? Color.secondary : Color.orange
                        )
                }
                .accessibilityLabel(
                    "\(count.category.label), \(count.importedCount) imported of \(count.sourceCount) in the source"
                )
            }
        } header: {
            Text("Integrity report")
        } footer: {
            Text("Source counts come from the TV Time archive. Imported counts show what this preview can restore.")
        }
    }
}

private struct ImportWarningsSection: View {
    let warnings: [ImportWarning]

    var body: some View {
        Section("Warnings") {
            ForEach(warnings) { warning in
                Label(warning.message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }
}

private enum LibraryExportKind {
    case json
    case titlesCSV
    case eventsCSV
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
