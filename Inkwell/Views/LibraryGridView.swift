import SwiftUI

/// GoodNotes-style launch view: a grid of notebook covers.
struct LibraryGridView: View {
    var onOpen: (UUID) -> Void

    @Environment(LibraryStore.self) private var library
    @State private var action: NotebookAction?

    var body: some View {
        NavigationStack {
            Group {
                if library.notebooks.isEmpty {
                    ContentUnavailableView {
                        Label("No Notebooks", systemImage: "book.closed")
                    } description: {
                        Text("Create your first notebook to start writing.")
                    } actions: {
                        Button("Create Notebook") { action = .newNotebook }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 180, maximum: 300), spacing: 20)],
                            spacing: 26
                        ) {
                            ForEach(library.notebooks) { notebook in
                                coverCard(notebook)
                            }
                        }
                        .padding(24)
                    }
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        action = .newNotebook
                    } label: {
                        Label("New Notebook", systemImage: "plus")
                    }
                }
            }
            .notebookActions(action: $action, onNotebookCreated: onOpen)
        }
    }

    private func coverCard(_ notebook: Notebook) -> some View {
        Button {
            onOpen(notebook.id)
        } label: {
            NotebookCover(notebook: notebook)
        }
        .buttonStyle(.plain)
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
