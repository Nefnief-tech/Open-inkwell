import Foundation

/// A notebook holds an ordered list of pages.
struct Notebook: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var pages: [PageInfo]
}

/// Metadata for a single page. The stroke data itself lives in a
/// `Pages/<id>.drawing` file next to the notebook manifest.
struct PageInfo: Identifiable, Codable, Hashable {
    let id: UUID
    var createdAt: Date
    var updatedAt: Date
}
