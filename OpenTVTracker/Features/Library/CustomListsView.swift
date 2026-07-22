import SwiftUI

struct CustomListsView: View {
    @Environment(AppModel.self) private var model
    @State private var nameRequest: CustomListNameRequest?
    @State private var pendingDelete: MediaList?
    @State private var showsDeleteConfirmation = false

    var body: some View {
        List {
            Section("My lists") {
                ForEach(model.lists) { list in
                    NavigationLink(value: CustomListRoute(id: list.id)) {
                        CustomListRow(
                            name: list.name,
                            count: model.titles(inList: list.id).count,
                            isShared: model.isListShared(list.id)
                        )
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            pendingDelete = list
                            showsDeleteConfirmation = true
                        }
                        Button("Rename", systemImage: "pencil") {
                            nameRequest = .rename(list)
                        }
                        .tint(.blue)
                    }
                }
                .onMove(perform: model.moveLists)
            }

            if !model.partnerSharedLists.isEmpty {
                Section("Shared with you") {
                    ForEach(model.partnerSharedLists) { list in
                        NavigationLink(value: SharedListRoute(id: list.id)) {
                            CustomListRow(
                                name: list.name,
                                count: model.titles(inSharedList: list.id).count,
                                isShared: true
                            )
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if model.lists.isEmpty, model.partnerSharedLists.isEmpty {
                ContentUnavailableView(
                    "No custom lists",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Create a private list for franchises, comfort shows, cinema plans, or any queue.")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
                    .disabled(model.lists.isEmpty)
            }
            ToolbarSpacer(.fixed)
            ToolbarItem(placement: .topBarTrailing) {
                Button("Create list", systemImage: "plus") {
                    nameRequest = .create
                }
            }
        }
        .sheet(item: $nameRequest) { request in
            CustomListNameView(request: request)
        }
        .alert("Delete list?", isPresented: $showsDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let pendingDelete {
                    model.deleteList(pendingDelete.id)
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            Text("This removes \(pendingDelete?.name ?? "the list") from this device and from partner sharing.")
        }
        .navigationDestination(for: CustomListRoute.self) { route in
            CustomListDetailView(listID: route.id)
        }
        .navigationDestination(for: SharedListRoute.self) { route in
            SharedListDetailView(listID: route.id)
        }
    }
}

struct CustomListDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let listID: MediaList.ID
    @State private var presentedSheet: CustomListSheet?
    @State private var showsDeleteConfirmation = false

    var body: some View {
        ZStack {
            AmbientBackdrop()

            if let list {
                List {
                    ForEach(model.titles(inList: list.id)) { title in
                        NavigationLink(value: title) {
                            ListTitleRow(title: title)
                        }
                        .listRowBackground(Color.clear)
                    }
                    .onDelete { model.removeTitles(at: $0, fromList: list.id) }
                    .onMove { model.moveTitles(inList: list.id, fromOffsets: $0, toOffset: $1) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .overlay {
                    if model.titles(inList: list.id).isEmpty {
                        ContentUnavailableView(
                            "This list is empty",
                            systemImage: "rectangle.stack.badge.plus",
                            description: Text("Add a movie or show, then drag to keep your preferred order.")
                        )
                    }
                }
            } else {
                ContentUnavailableView("List unavailable", systemImage: "questionmark.folder")
            }
        }
        .navigationTitle(list?.name ?? "Custom list")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
                    .disabled(list.map { model.titles(inList: $0.id).isEmpty } ?? true)
            }
            ToolbarSpacer(.fixed)
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add titles", systemImage: "plus") {
                    presentedSheet = .titlePicker(listID)
                }
                .disabled(list == nil)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu("List actions", systemImage: "ellipsis") {
                    Button("Rename", systemImage: "pencil") {
                        if let list {
                            presentedSheet = .name(.rename(list))
                        }
                    }
                    if model.isListShared(listID) {
                        Button("Stop sharing", systemImage: "person.2.slash") {
                            model.stopSharingList(listID)
                        }
                    } else {
                        Button("Share with partner", systemImage: "person.2") {
                            model.shareListWithPartner(listID)
                        }
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        showsDeleteConfirmation = true
                    }
                }
                .disabled(list == nil)
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .name(let request):
                CustomListNameView(request: request)
            case .titlePicker(let listID):
                CustomListTitlePickerView(listID: listID)
            }
        }
        .alert("Delete list?", isPresented: $showsDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                model.deleteList(listID)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the list from this device and from partner sharing.")
        }
    }

    private var list: MediaList? {
        model.lists.first { $0.id == listID }
    }
}

struct SharedListDetailView: View {
    @Environment(AppModel.self) private var model
    let listID: SharedMediaList.ID

    var body: some View {
        ZStack {
            AmbientBackdrop()

            if let list = model.sharedList(withID: listID) {
                List(model.titles(inSharedList: list.id)) { title in
                    NavigationLink(value: title) {
                        ListTitleRow(title: title)
                    }
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .overlay {
                    if model.titles(inSharedList: list.id).isEmpty {
                        ContentUnavailableView("This shared list is empty", systemImage: "person.2")
                    }
                }
            } else {
                ContentUnavailableView("Shared list unavailable", systemImage: "person.2.slash")
            }
        }
        .navigationTitle(model.sharedList(withID: listID)?.name ?? "Shared list")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CustomListTitlePickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let listID: MediaList.ID
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List(filteredTitles) { title in
                Button {
                    model.toggleTitle(title.id, inList: listID)
                } label: {
                    HStack {
                        ListTitleRow(title: title)
                        Spacer()
                        Image(systemName: model.isTitle(title.id, inList: listID) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(model.isTitle(title.id, inList: listID) ? Color.accentColor : .secondary)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityValue(model.isTitle(title.id, inList: listID) ? "Added" : "Not added")
            }
            .searchable(text: $query, prompt: "Search your library")
            .navigationTitle("Add titles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var filteredTitles: [MediaTitle] {
        guard !query.isEmpty else { return model.titles }
        return model.titles.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }
}

struct CustomListRow: View {
    let name: String
    let count: Int
    let isShared: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isShared ? "person.2.fill" : "list.bullet.rectangle")
                .foregroundStyle(isShared ? Color.accentColor : .secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.headline)
                Text("\(count) \(count == 1 ? "title" : "titles")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(isShared ? "Shared privately" : "Private")
    }
}

private struct ListTitleRow: View {
    let title: MediaTitle

    var body: some View {
        HStack(spacing: 12) {
            PosterArtwork(title: title, cornerRadius: 8)
                .frame(width: 48, height: 68)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title.title)
                    .font(.headline)
                    .lineLimit(2)
                Text("\(title.year) · \(title.kind.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct CustomListRoute: Hashable {
    let id: MediaList.ID
}

struct SharedListRoute: Hashable {
    let id: SharedMediaList.ID
}

private enum CustomListSheet: Identifiable {
    case name(CustomListNameRequest)
    case titlePicker(MediaList.ID)

    var id: String {
        switch self {
        case .name(let request): request.id
        case .titlePicker(let id): "titles-\(id)"
        }
    }
}

#Preview {
    NavigationStack {
        CustomListsView()
            .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
            .environment(\.allowsRemoteArtwork, false)
    }
}
