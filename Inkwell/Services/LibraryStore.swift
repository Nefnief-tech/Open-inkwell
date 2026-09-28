import Foundation
import Observation
import PencilKit
import UIKit

/// Single source of truth for notebooks, pages, and their on-disk data.
///
/// Layout under Documents/Notebooks/<notebook-uuid>/:
///   notebook.json          — Notebook manifest (encoded with ISO-8601 dates)
///   Pages/<page-uuid>.drawing   — PKDrawing data
///   Thumbs/<page-uuid>.png      — page thumbnail (paper template + ink) for the gallery
@MainActor
@Observable
final class LibraryStore {
    private(set) var notebooks: [Notebook] = []

    private let fileManager = FileManager.default
    private let thumbCache = NSCache<NSUUID, UIImage>()

    // MARK: - Paths

    private var rootURL: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appending(path: "Notebooks", directoryHint: .isDirectory)
    }

    private func notebookURL(_ id: UUID) -> URL {
        rootURL.appending(component: id.uuidString, directoryHint: .isDirectory)
    }

    private func manifestURL(_ id: UUID) -> URL {
        notebookURL(id).appending(path: "notebook.json")
    }

    private func drawingURL(_ notebookID: UUID, _ pageID: UUID) -> URL {
        notebookURL(notebookID).appending(path: "Pages/\(pageID.uuidString).drawing")
    }

    private func thumbnailURL(_ notebookID: UUID, _ pageID: UUID) -> URL {
        notebookURL(notebookID).appending(path: "Thumbs/\(pageID.uuidString).png")
    }

    // MARK: - Loading

    init() {
        loadAll()
    }

    func loadAll() {
        let dirs = (try? fileManager.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: nil
        )) ?? []
        var found: [Notebook] = []
        for dir in dirs where dir.hasDirectoryPath {
            guard let data = try? Data(contentsOf: dir.appending(path: "notebook.json")),
                  let nb = try? decoder.decode(Notebook.self, from: data) else { continue }
            found.append(nb)
        }
        notebooks = found.sorted { $0.updatedAt > $1.updatedAt }
    }

    func notebook(id: UUID?) -> Notebook? {
        guard let id else { return nil }
        return notebooks.first { $0.id == id }
    }

    // MARK: - Notebook CRUD

    @discardableResult
    func createNotebook(named name: String, coverColorIndex: Int = Int.random(in: 0..<CoverPalette.themes.count)) -> Notebook {
        let nb = Notebook(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled Notebook" : name,
            createdAt: .now,
            updatedAt: .now,
            coverColorIndex: coverColorIndex
        )
        try? fileManager.createDirectory(at: notebookURL(nb.id), withIntermediateDirectories: true)
        notebooks.insert(nb, at: 0)
        persist(nb)
        return nb
    }

    func renameNotebook(_ id: UUID, to name: String) {
        guard let idx = notebooks.firstIndex(where: { $0.id == id }) else { return }
        notebooks[idx].name = name
        notebooks[idx].updatedAt = .now
        persist(notebooks[idx])
    }

    func setCoverColor(_ id: UUID, colorIndex: Int) {
        guard let idx = notebooks.firstIndex(where: { $0.id == id }) else { return }
        notebooks[idx].coverColorIndex = colorIndex
        persist(notebooks[idx])
    }

    func setTemplate(_ id: UUID, template: PaperTemplate) {
        guard let idx = notebooks.firstIndex(where: { $0.id == id }) else { return }
        notebooks[idx].template = template
        persist(notebooks[idx])
    }

    /// Copies the whole notebook directory (drawings + thumbnails included),
    /// then rewrites the manifest with a new identity.
    @discardableResult
    func duplicateNotebook(_ id: UUID) -> Notebook? {
        guard let original = notebook(id: id) else { return nil }
        let newID = UUID()
        do {
            try fileManager.copyItem(at: notebookURL(id), to: notebookURL(newID))
        } catch {
            return nil
        }
        let copy = Notebook(
            id: newID,
            name: "\(original.name) Copy",
            createdAt: .now,
            updatedAt: .now,
            coverColorIndex: original.coverColorIndex,
            template: original.template,
            pages: original.pages
        )
        persist(copy)
        notebooks.insert(copy, at: 0)
        return copy
    }

    func deleteNotebook(_ id: UUID) {
        try? fileManager.removeItem(at: notebookURL(id))
        notebooks.removeAll { $0.id == id }
    }

    // MARK: - Page CRUD

    @discardableResult
    func createPage(in notebookID: UUID, template: PaperTemplate? = nil) -> PageInfo? {
        guard let idx = notebooks.firstIndex(where: { $0.id == notebookID }) else { return nil }
        let page = PageInfo(id: UUID(), createdAt: .now, updatedAt: .now,
                            template: template ?? notebooks[idx].template)
        notebooks[idx].pages.append(page)
        notebooks[idx].updatedAt = .now
        persist(notebooks[idx])
        return page
    }

    func deletePage(_ pageID: UUID, in notebookID: UUID) {
        guard let idx = notebooks.firstIndex(where: { $0.id == notebookID }) else { return }
        notebooks[idx].pages.removeAll { $0.id == pageID }
        notebooks[idx].updatedAt = .now
        persist(notebooks[idx])
        try? fileManager.removeItem(at: drawingURL(notebookID, pageID))
        try? fileManager.removeItem(at: thumbnailURL(notebookID, pageID))
        thumbCache.removeObject(forKey: pageID as NSUUID)
    }

    // MARK: - Drawing I/O

    func loadDrawing(notebookID: UUID, pageID: UUID) async -> PKDrawing {
        let url = drawingURL(notebookID, pageID)
        return await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url) else { return PKDrawing() }
            return (try? PKDrawing(data: data)) ?? PKDrawing()
        }.value
    }

    func savePageDrawing(
        notebookID: UUID,
        pageID: UUID,
        drawing: PKDrawing,
        pageSize: CGSize,
        scale: CGFloat,
        template: PaperTemplate
    ) async {
        let fallback = CGSize(width: 1180, height: 820) // iPad 10.9" portrait points
        let rect = pageSize.width > 0 && pageSize.height > 0
            ? CGRect(origin: .zero, size: pageSize)
            : CGRect(origin: .zero, size: fallback)

        let payload = await Task.detached(priority: .utility) { () -> (drawing: Data, thumb: Data?) in
            let drawingData = drawing.dataRepresentation()

            let format = UIGraphicsImageRendererFormat()
            format.scale = scale == 0 ? 2 : scale
            let renderer = UIGraphicsImageRenderer(bounds: rect, format: format)
            let image = renderer.image { context in
                let cg = context.cgContext
                cg.setFillColor(PaperTheme.uiPaper.cgColor)
                cg.fill(rect)
                template.draw(in: cg, rect: rect, color: PaperTheme.uiLine)
                drawing.image(from: rect, scale: format.scale).draw(in: rect)
            }
            return (drawingData, image.pngData())
        }.value

        let drawingDest = drawingURL(notebookID, pageID)
        let thumbDest = thumbnailURL(notebookID, pageID)
        try? fileManager.createDirectory(at: drawingDest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: thumbDest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? payload.drawing.write(to: drawingDest, options: .atomic)
        if let png = payload.thumb {
            try? png.write(to: thumbDest, options: .atomic)
        }

        if let idx = notebooks.firstIndex(where: { $0.id == notebookID }) {
            if let pidx = notebooks[idx].pages.firstIndex(where: { $0.id == pageID }) {
                notebooks[idx].pages[pidx].updatedAt = .now
            }
            notebooks[idx].updatedAt = .now
            persist(notebooks[idx])
        }
    }

    func loadThumbnail(notebookID: UUID, pageID: UUID) async -> UIImage? {
        if let cached = thumbCache.object(forKey: pageID as NSUUID) { return cached }
        let url = thumbnailURL(notebookID, pageID)
        let image = await Task.detached(priority: .utility) {
            UIImage(contentsOfFile: url.path)
        }.value
        if let image {
            thumbCache.setObject(image, forKey: pageID as NSUUID)
        }
        return image
    }

    // MARK: - Helpers

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private func persist(_ nb: Notebook) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(nb) else { return }
        try? fileManager.createDirectory(at: notebookURL(nb.id), withIntermediateDirectories: true)
        try? data.write(to: manifestURL(nb.id), options: .atomic)
    }
}
