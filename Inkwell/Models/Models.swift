import Foundation

/// A notebook holds an ordered list of pages, plus its cover appearance and
/// default paper template. Custom Codable so files written by older versions
/// (before covers/templates) still decode with sensible defaults.
struct Notebook: Identifiable, Hashable {
    let id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var coverColorIndex: Int
    var template: PaperTemplate
    var pages: [PageInfo]
}

/// Metadata for a single page. Stroke data lives in `Pages/<id>.drawing`,
/// thumbnails in `Thumbs/<id>.png` next to the notebook manifest.
struct PageInfo: Identifiable, Hashable {
    let id: UUID
    var createdAt: Date
    var updatedAt: Date
    var template: PaperTemplate
}

extension Notebook: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, createdAt, updatedAt, coverColorIndex, template, pages
    }

    init(id: UUID, name: String, createdAt: Date, updatedAt: Date,
         coverColorIndex: Int = 0, template: PaperTemplate = .plain, pages: [PageInfo] = []) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.coverColorIndex = coverColorIndex
        self.template = template
        self.pages = pages
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        coverColorIndex = try c.decodeIfPresent(Int.self, forKey: .coverColorIndex) ?? 0
        template = try c.decodeIfPresent(PaperTemplate.self, forKey: .template) ?? .plain
        pages = try c.decode([PageInfo].self, forKey: .pages)
    }
}

extension PageInfo: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, createdAt, updatedAt, template
    }

    init(id: UUID, createdAt: Date, updatedAt: Date, template: PaperTemplate = .plain) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.template = template
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        template = try c.decodeIfPresent(PaperTemplate.self, forKey: .template) ?? .plain
    }
}
