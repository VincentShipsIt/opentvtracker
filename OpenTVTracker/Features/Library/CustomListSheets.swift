import SwiftUI

struct AddToListsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let title: MediaTitle

    var body: some View {
        NavigationStack {
            List(model.lists) { list in
                Button {
                    model.toggleTitle(title.id, inList: list.id)
                } label: {
                    HStack {
                        CustomListRow(
                            name: list.name,
                            count: model.titles(inList: list.id).count,
                            isShared: model.isListShared(list.id)
                        )
                        Spacer()
                        Image(systemName: selectionSymbol(for: list))
                            .foregroundStyle(selectionColor(for: list))
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityValue(model.isTitle(title.id, inList: list.id) ? "Added" : "Not added")
            }
            .overlay {
                if model.lists.isEmpty {
                    ContentUnavailableView(
                        "No custom lists",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Create a list from Library first.")
                    )
                }
            }
            .navigationTitle("Add \(title.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func selectionSymbol(for list: MediaList) -> String {
        model.isTitle(title.id, inList: list.id) ? "checkmark.circle.fill" : "circle"
    }

    private func selectionColor(for list: MediaList) -> Color {
        model.isTitle(title.id, inList: list.id) ? .accentColor : .secondary
    }
}

struct CustomListNameView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: CustomListNameRequest
    @State private var name: String
    @State private var validationMessage: String?

    init(request: CustomListNameRequest) {
        self.request = request
        _name = State(initialValue: request.initialName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Comfort shows", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }
                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(request.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        let succeeded: Bool
        switch request.mode {
        case .create:
            succeeded = model.createList(named: name) != nil
        case .rename(let id):
            succeeded = model.renameList(id, to: name)
        }
        if succeeded {
            dismiss()
        } else {
            validationMessage = "Choose a non-empty name that is not already in use."
        }
    }
}

struct CustomListNameRequest: Identifiable {
    enum Mode {
        case create
        case rename(MediaList.ID)
    }

    let mode: Mode
    let initialName: String

    static let create = CustomListNameRequest(mode: .create, initialName: "")

    static func rename(_ list: MediaList) -> CustomListNameRequest {
        CustomListNameRequest(mode: .rename(list.id), initialName: list.name)
    }

    var id: String {
        switch mode {
        case .create: "create"
        case .rename(let id): "rename-\(id)"
        }
    }

    var navigationTitle: String {
        switch mode {
        case .create: "New list"
        case .rename: "Rename list"
        }
    }
}
