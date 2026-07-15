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
    @State private var importPreview: LibraryImportPreview?
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
                    Button("Import JSON or CSV", systemImage: "square.and.arrow.down") {
                        showsImporter = true
                    }
                } footer: {
                    Text("OpenTV previews matches, duplicates, and skipped rows before changing your library. Reimporting the same file is safe.")
                }

                if let importPreview {
                    Section("Import preview") {
                        LabeledContent("Matched", value: String(importPreview.matchedCount))
                        LabeledContent("New", value: String(importPreview.addedCount))
                        LabeledContent("Duplicates", value: String(importPreview.duplicateCount))
                        LabeledContent("Skipped", value: String(importPreview.skippedCount))

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
                allowedContentTypes: [.json, .commaSeparatedText]
            ) { result in
                importFile(result)
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
            }
            exportDocument = LibraryExportDocument(data: data)
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
            importPreview = try LibraryTransferService.previewImport(data, into: model.snapshot)
            statusMessage = nil
        } catch {
            importPreview = nil
            statusMessage = error.localizedDescription
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
