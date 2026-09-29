import Foundation
import Observation
import UIKit

/// Persistence + CRUD for rendered documents.
///
/// Layout under Documents/InkDocs/<doc-uuid>/:
///   doc.json   — HandDocument manifest
///   bg.jpg     — imported background image (if any)
///   thumb.png  — small rendered preview for the list
@MainActor
@Observable
final class DocumentStore {
    private(set) var documents: [HandDocument] = []

    private let fileManager = FileManager.default
    private let thumbCache = NSCache<NSUUID, UIImage>()

    // MARK: - Paths

    private var rootURL: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appending(path: "InkDocs", directoryHint: .isDirectory)
    }

    private func docURL(_ id: UUID) -> URL {
        rootURL.appending(component: id.uuidString, directoryHint: .isDirectory)
    }

    private func manifestURL(_ id: UUID) -> URL {
        docURL(id).appending(path: "doc.json")
    }

    private func backgroundURL(_ id: UUID) -> URL {
        docURL(id).appending(path: "bg.jpg")
    }

    private func thumbURL(_ id: UUID) -> URL {
        docURL(id).appending(path: "thumb.png")
    }

    // MARK: - Loading

    init() {
        let dirs = (try? fileManager.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: nil
        )) ?? []
        var found: [HandDocument] = []
        for dir in dirs where dir.hasDirectoryPath {
            guard let data = try? Data(contentsOf: dir.appending(path: "doc.json")),
                  var doc = try? JSONDecoder.iso.decode(HandDocument.self, from: data) else { continue }
            // One-time migration: text size used to be coupled to line
            // spacing. Fold the old coupling into sizeMultiplier so the
            // rendered look is preserved, then mark as migrated.
            if doc.layoutVersion == 0 {
                doc.sizeMultiplier *= doc.lineSpacing / GlyphRenderer.naturalLineSpacing
                doc.layoutVersion = 1
                persist(doc)
            }
            found.append(doc)
        }
        documents = found.sorted { $0.updatedAt > $1.updatedAt }
    }

    func document(id: UUID?) -> HandDocument? {
        guard let id else { return nil }
        return documents.first { $0.id == id }
    }

    // MARK: - CRUD

    @discardableResult
    func createDocument(handID: UUID, name: String) -> HandDocument {
        let doc = HandDocument(id: UUID(), name: name, handID: handID,
                               createdAt: .now, updatedAt: .now)
        try? fileManager.createDirectory(at: docURL(doc.id), withIntermediateDirectories: true)
        documents.insert(doc, at: 0)
        persist(doc)
        return doc
    }

    func update(_ doc: HandDocument) {
        guard let idx = documents.firstIndex(where: { $0.id == doc.id }) else { return }
        var updated = doc
        updated.updatedAt = .now
        documents[idx] = updated
        persist(updated)
    }

    func renameDocument(_ id: UUID, to name: String) {
        guard var doc = document(id: id) else { return }
        doc.name = name
        update(doc)
    }

    func deleteDocument(_ id: UUID) {
        try? fileManager.removeItem(at: docURL(id))
        documents.removeAll { $0.id == id }
        thumbCache.removeObject(forKey: id as NSUUID)
    }

    /// Copies the manifest plus background/thumbnail files under a new id.
    @discardableResult
    func duplicateDocument(_ id: UUID) -> HandDocument? {
        guard let doc = document(id: id) else { return nil }
        let copy = HandDocument(
            id: UUID(),
            name: "\(doc.name) Copy",
            handID: doc.handID,
            text: doc.text,
            usesBackgroundImage: doc.usesBackgroundImage,
            template: doc.template,
            lineSpacing: doc.lineSpacing,
            letterSpacing: doc.letterSpacing,
            sizeMultiplier: doc.sizeMultiplier,
            inkColorIndex: doc.inkColorIndex,
            leftMargin: doc.leftMargin,
            firstBaseline: doc.firstBaseline,
            variationSeed: Int.random(in: 0...Int(Int32.max)),
            layoutVersion: doc.layoutVersion,
            createdAt: .now,
            updatedAt: .now
        )
        try? fileManager.createDirectory(at: docURL(copy.id), withIntermediateDirectories: true)
        for file in ["bg.jpg", "thumb.png"] {
            let source = docURL(id).appending(path: file)
            if fileManager.fileExists(atPath: source.path) {
                try? fileManager.copyItem(at: source, to: docURL(copy.id).appending(path: file))
            }
        }
        documents.insert(copy, at: 0)
        persist(copy)
        return copy
    }

    // MARK: - Background image

    /// Downscales to a max edge of 2400 px and stores as JPEG.
    func saveBackground(docID: UUID, imageData: Data) async {
        let dest = backgroundURL(docID)
        let stored = await Task.detached(priority: .utility) { () -> Data? in
            guard var image = UIImage(data: imageData) else { return nil }
            let maxEdge: CGFloat = 2400
            let largest = max(image.size.width, image.size.height) * image.scale
            if largest > maxEdge {
                let s = maxEdge / largest
                let newSize = CGSize(width: image.size.width * s, height: image.size.height * s)
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                image = UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
                    image.draw(in: CGRect(origin: .zero, size: newSize))
                }
            }
            return image.jpegData(compressionQuality: 0.9)
        }.value
        guard let stored else { return }
        try? fileManager.createDirectory(at: docURL(docID), withIntermediateDirectories: true)
        try? stored.write(to: dest, options: .atomic)
        if var doc = document(id: docID) {
            doc.usesBackgroundImage = true
            update(doc)
        }
        thumbCache.removeObject(forKey: docID as NSUUID)
    }

    func removeBackground(docID: UUID) {
        try? fileManager.removeItem(at: backgroundURL(docID))
        if var doc = document(id: docID) {
            doc.usesBackgroundImage = false
            update(doc)
        }
        thumbCache.removeObject(forKey: docID as NSUUID)
    }

    func loadBackground(docID: UUID) async -> UIImage? {
        let url = backgroundURL(docID)
        return await Task.detached(priority: .userInitiated) {
            UIImage(contentsOfFile: url.path)
        }.value
    }

    // MARK: - Preview thumbnail

    func saveThumbnail(docID: UUID, image: UIImage) {
        let url = thumbURL(docID)
        try? fileManager.createDirectory(at: docURL(docID), withIntermediateDirectories: true)
        try? image.pngData()?.write(to: url, options: .atomic)
        thumbCache.setObject(image, forKey: docID as NSUUID)
    }

    func loadThumbnail(docID: UUID) async -> UIImage? {
        if let cached = thumbCache.object(forKey: docID as NSUUID) { return cached }
        let url = thumbURL(docID)
        let image = await Task.detached(priority: .utility) {
            UIImage(contentsOfFile: url.path)
        }.value
        if let image {
            thumbCache.setObject(image, forKey: docID as NSUUID)
        }
        return image
    }

    // MARK: - Helpers

    private func persist(_ doc: HandDocument) {
        guard let data = try? JSONEncoder.iso.encode(doc) else { return }
        try? fileManager.createDirectory(at: docURL(doc.id), withIntermediateDirectories: true)
        try? data.write(to: manifestURL(doc.id), options: .atomic)
    }
}
