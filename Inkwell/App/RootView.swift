import SwiftUI

/// Sidebar sections: capture handwriting sets, or create rendered documents.
enum SidebarSection: Hashable {
    case hands
    case documents
}

struct RootView: View {
    @State private var selection: SidebarSection? = .hands
    @State private var showSettings = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    Label("My Hands", systemImage: "hand.draw")
                        .tag(SidebarSection.hands)
                    Label("Documents", systemImage: "doc.on.doc")
                        .tag(SidebarSection.documents)
                } footer: {
                    Text("Capture your handwriting once, then render any typed text in it.")
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Inkwell")
            .toolbar {
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
        } detail: {
            switch selection {
            case .documents:
                DocumentsListView()
            default:
                HandsListView()
            }
        }
    }
}
