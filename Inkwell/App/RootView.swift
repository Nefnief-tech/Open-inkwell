import SwiftUI

struct RootView: View {
    @Environment(LibraryStore.self) private var library
    @State private var selection: Notebook.ID?

    var body: some View {
        NavigationSplitView {
            NotebooksSidebar(selection: $selection)
        } detail: {
            if let selection, library.notebook(id: selection) != nil {
                PagesGrid(notebookID: selection)
            } else {
                ContentUnavailableView(
                    "No Notebook Selected",
                    systemImage: "book.closed",
                    description: Text("Create a notebook in the sidebar to start writing.")
                )
            }
        }
    }
}
