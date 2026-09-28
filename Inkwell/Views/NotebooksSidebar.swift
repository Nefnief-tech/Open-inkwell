import SwiftUI

struct NotebooksSidebar: View {
    @Binding var selection: SidebarItem?
    @Environment(LibraryStore.self) private var library

    @State private var action: NotebookAction?
    @State private var showSettings = false

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("All Notebooks", systemImage: "books.vertical.fill")
                    .tag(SidebarItem.library)
            }

            Section("Notebooks") {
                ForEach(library.notebooks) { notebook in
                    row(notebook)
                        .tag(SidebarItem.notebook(notebook.id))
                        .contextMenu {
                            Button {
                                action = .rename(notebook.id)
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Button {
                                action = .changeCover(notebook.id)
                            } label: {
                                Label("Change Cover", systemImage: "paintpalette")
                            }
                            Button {
                                library.duplicateNotebook(notebook.id)
                            } label: {
                                Label("Duplicate", systemImage: "plus.square.on.square")
                            }
                            Divider()
                            Button(role: .destructive) {
                                action = .delete(notebook.id)
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
                    action = .newNotebook
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
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .notebookActions(action: $action, onNotebookCreated: { selection = .notebook($0) })
    }

    private func row(_ notebook: Notebook) -> some View {
        HStack(spacing: 12) {
            MiniCover(notebook: notebook)
            VStack(alignment: .leading, spacing: 2) {
                Text(notebook.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text("\(notebook.pages.count) page\(notebook.pages.count == 1 ? "" : "s") · \(notebook.updatedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}
