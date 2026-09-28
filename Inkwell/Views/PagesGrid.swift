import SwiftUI

struct PagesGrid: View {
    let notebookID: UUID

    @Environment(LibraryStore.self) private var library
    @State private var path: [PageInfo] = []

    private var notebook: Notebook? { library.notebook(id: notebookID) }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let notebook {
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 200, maximum: 320), spacing: 20)],
                            spacing: 24
                        ) {
                            ForEach(Array(notebook.pages.enumerated()), id: \.element.id) { index, page in
                                PageCell(notebookID: notebookID, page: page, index: index)
                            }
                        }
                        .padding(24)
                    }
                    .navigationTitle(notebook.name)
                } else {
                    ContentUnavailableView("Notebook Deleted", systemImage: "trash")
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if let page = library.createPage(in: notebookID) {
                            path.append(page)
                        }
                    } label: {
                        Label("New Page", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(for: PageInfo.self) { page in
                DrawingView(notebookID: notebookID, page: page)
            }
        }
    }
}

private struct PageCell: View {
    let notebookID: UUID
    let page: PageInfo
    let index: Int

    @Environment(LibraryStore.self) private var library
    @State private var thumbnail: UIImage?
    @State private var confirmingDelete = false

    var body: some View {
        NavigationLink(value: page) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(uiColor: .systemBackground))
                        .shadow(color: .black.opacity(0.14), radius: 8, y: 4)
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else {
                        Image(systemName: "pencil.tip.crop.circle")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                    }
                }
                .aspectRatio(0.75, contentMode: .fit)
                .overlay(alignment: .bottomTrailing) {
                    Text("\(index + 1)")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .padding(6)
                        .background(.regularMaterial, in: Circle())
                        .padding(8)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Label("Delete Page", systemImage: "trash")
            }
        }
        .confirmationDialog(
            "Delete this page? This cannot be undone.",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Page", role: .destructive) {
                library.deletePage(page.id, in: notebookID)
            }
        }
        .task(id: page.id) {
            thumbnail = await library.loadThumbnail(notebookID: notebookID, pageID: page.id)
        }
    }
}
