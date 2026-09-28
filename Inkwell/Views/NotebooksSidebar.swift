import SwiftUI

struct NotebooksSidebar: View {
    @Binding var selection: Notebook.ID?
    @Environment(LibraryStore.self) private var library

    @State private var showNewNotebook = false
    @State private var newNotebookName = ""
    @State private var renaming: Notebook?
    @State private var renameText = ""
    @State private var deleting: Notebook?
    @State private var showSettings = false

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                ForEach(library.notebooks) { notebook in
                    NotebookRow(notebook: notebook)
                        .contextMenu {
                            Button {
                                renameText = notebook.name
                                renaming = notebook
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                deleting = notebook
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Inkwell")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newNotebookName = ""
                    showNewNotebook = true
                } label: {
                    Label("New Notebook", systemImage: "plus")
                }
            }
            ToolbarItem {
                Button {
                    showSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .alert("New Notebook", isPresented: $showNewNotebook) {
            TextField("Name", text: $newNotebookName)
            Button("Create") {
                let nb = library.createNotebook(named: newNotebookName)
                selection = nb.id
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Rename Notebook",
            isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            )
        ) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let nb = renaming {
                    library.renameNotebook(nb.id, to: renameText)
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog(
            "Delete “\(deleting?.name ?? "")”? All of its pages will be removed.",
            isPresented: Binding(
                get: { deleting != nil },
                set: { if !$0 { deleting = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Notebook", role: .destructive) {
                if let nb = deleting {
                    if selection == nb.id { selection = nil }
                    library.deleteNotebook(nb.id)
                }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}

private struct NotebookRow: View {
    let notebook: Notebook

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "book.closed.fill")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(notebook.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text("\(notebook.pages.count) page\(notebook.pages.count == 1 ? "" : "s") · \(notebook.updatedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
