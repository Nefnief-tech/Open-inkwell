import SwiftUI

/// Sidebar selection: the library grid, or a specific notebook.
enum SidebarItem: Hashable {
    case library
    case notebook(UUID)
}

struct RootView: View {
    @Environment(LibraryStore.self) private var library
    @State private var selection: SidebarItem? = .library

    var body: some View {
        NavigationSplitView {
            NotebooksSidebar(selection: $selection)
        } detail: {
            switch selection {
            case .notebook(let id) where library.notebook(id: id) != nil:
                PagesGrid(notebookID: id)
            default:
                LibraryGridView(onOpen: { selection = .notebook($0) })
            }
        }
    }
}
