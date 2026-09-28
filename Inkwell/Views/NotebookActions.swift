import SwiftUI

/// Actions that open a management sheet for a notebook.
enum NotebookAction: Identifiable, Hashable {
    case newNotebook
    case rename(UUID)
    case changeCover(UUID)
    case delete(UUID)

    var id: String {
        switch self {
        case .newNotebook: return "new"
        case .rename(let id): return "rename-\(id.uuidString)"
        case .changeCover(let id): return "cover-\(id.uuidString)"
        case .delete(let id): return "delete-\(id.uuidString)"
        }
    }
}

/// Attach with `.notebookActions(action:onNotebookCreated:)` to any view that
/// triggers notebook management; renders the corresponding sheet.
struct NotebookActionsModifier: ViewModifier {
    @Binding var action: NotebookAction?
    var onNotebookCreated: (UUID) -> Void

    @Environment(LibraryStore.self) private var library
    @State private var text = ""

    func body(content: Content) -> some View {
        content.sheet(item: $action) { act in
            switch act {
            case .newNotebook:
                nameSheet(title: "New Notebook", button: "Create") {
                    let nb = library.createNotebook(named: text)
                    text = ""
                    onNotebookCreated(nb.id)
                }
            case .rename(let id):
                nameSheet(title: "Rename Notebook", button: "Rename") {
                    if let nb = library.notebook(id: id) {
                        library.renameNotebook(id, to: text.isEmpty ? nb.name : text)
                    }
                    text = ""
                }
                .onAppear {
                    text = library.notebook(id: id)?.name ?? ""
                }
            case .changeCover(let id):
                coverSheet(id)
            case .delete(let id):
                deleteSheet(id)
            }
        }
    }

    private func nameSheet(title: String, button: String, onConfirm: @escaping () -> Void) -> some View {
        NavigationStack {
            Form {
                TextField("Name", text: $text)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { text = ""; action = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(button) { onConfirm(); action = nil }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func coverSheet(_ id: UUID) -> some View {
        let current = library.notebook(id: id)?.coverColorIndex ?? 0
        return NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 18)], spacing: 18) {
                    ForEach(CoverPalette.themes) { theme in
                        Button {
                            library.setCoverColor(id, colorIndex: theme.id)
                            action = nil
                        } label: {
                            ZStack {
                                LinearGradient(colors: [theme.light, theme.dark],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
                                if theme.id == current {
                                    Circle().strokeBorder(.white, lineWidth: 3)
                                        .padding(-6)
                                }
                            }
                            .clipShape(Circle())
                            .frame(width: 56, height: 56)
                            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                            .overlay(
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.white)
                                    .opacity(theme.id == current ? 1 : 0)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(24)
            }
            .navigationTitle("Cover Color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { action = nil }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func deleteSheet(_ id: UUID) -> some View {
        let name = library.notebook(id: id)?.name ?? "Notebook"
        return NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Label("Delete “\(name)”?", systemImage: "trash")
                    .font(.headline)
                Text("The notebook and all of its pages will be permanently removed. This cannot be undone.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive) {
                    library.deleteNotebook(id)
                    action = nil
                } label: {
                    Label("Delete Notebook", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button {
                    action = nil
                } label: {
                    Text("Cancel").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(24)
            .navigationTitle("Delete Notebook")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}

extension View {
    func notebookActions(action: Binding<NotebookAction?>,
                         onNotebookCreated: @escaping (UUID) -> Void = { _ in }) -> some View {
        modifier(NotebookActionsModifier(action: action, onNotebookCreated: onNotebookCreated))
    }
}
