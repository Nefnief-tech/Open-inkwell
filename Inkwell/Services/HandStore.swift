import Foundation
import Observation
import PencilKit

/// Persistence + CRUD for handwriting sets and their glyph variants.
///
/// Layout under Documents/Hands/<hand-uuid>/:
///   hand.json                       — HandwritingSet manifest
///   glyphs/<hex>.drawing            — variant 0 of a character
///   glyphs/<hex>-v<n>.drawing       — variant n ≥ 1
@MainActor
@Observable
final class HandStore {
    private(set) var hands: [HandwritingSet] = []

    private let fileManager = FileManager.default
    private let thumbCache = NSCache<NSString, UIImage>()
    private var glyphCache: [String: PKDrawing] = [:]

    // MARK: - Paths

    private var rootURL: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appending(path: "Hands", directoryHint: .isDirectory)
    }

    private func handURL(_ id: UUID) -> URL {
        rootURL.appending(component: id.uuidString, directoryHint: .isDirectory)
    }

    private func manifestURL(_ id: UUID) -> URL {
        handURL(id).appending(path: "hand.json")
    }

    private func glyphURL(_ handID: UUID, _ character: String, variant: Int) -> URL {
        let hex = character.unicodeScalars.map { String(format: "%04X", $0.value) }.joined()
        let name = variant <= 0 ? hex : "\(hex)-v\(variant)"
        return handURL(handID).appending(path: "glyphs/\(name).drawing")
    }

    // MARK: - Loading

    init() {
        let dirs = (try? fileManager.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: nil
        )) ?? []
        var found: [HandwritingSet] = []
        for dir in dirs where dir.hasDirectoryPath {
            guard let data = try? Data(contentsOf: dir.appending(path: "hand.json")),
                  let hand = try? JSONDecoder.iso.decode(HandwritingSet.self, from: data) else { continue }
            found.append(hand)
        }
        hands = found.sorted { $0.updatedAt > $1.updatedAt }
    }

    func hand(id: UUID?) -> HandwritingSet? {
        guard let id else { return nil }
        return hands.first { $0.id == id }
    }

    func variantCount(handID: UUID, character: String) -> Int {
        hand(id: handID)?.variantCount(character) ?? 0
    }

    // MARK: - CRUD

    @discardableResult
    func createHand(named name: String) -> HandwritingSet {
        let hand = HandwritingSet(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "My Handwriting" : name,
            createdAt: .now,
            updatedAt: .now
        )
        try? fileManager.createDirectory(at: handURL(hand.id).appending(path: "glyphs"), withIntermediateDirectories: true)
        hands.insert(hand, at: 0)
        persist(hand)
        return hand
    }

    func renameHand(_ id: UUID, to name: String) {
        guard let idx = hands.firstIndex(where: { $0.id == id }) else { return }
        hands[idx].name = name
        hands[idx].updatedAt = .now
        persist(hands[idx])
    }

    func deleteHand(_ id: UUID) {
        try? fileManager.removeItem(at: handURL(id))
        hands.removeAll { $0.id == id }
    }

    func setSpaceWidth(_ id: UUID, fraction: Double) {
        guard let idx = hands.firstIndex(where: { $0.id == id }) else { return }
        hands[idx].spaceWidth = fraction
        hands[idx].updatedAt = .now
        persist(hands[idx])
    }

    // MARK: - Glyphs

    func glyphDrawing(handID: UUID, character: String, variant: Int = 0) async -> PKDrawing? {
        let key = "\(handID.uuidString)-\(character)-\(variant)"
        if let cached = glyphCache[key] { return cached }
        let url = glyphURL(handID, character, variant: variant)
        let drawing = await Task.detached(priority: .userInitiated) { () -> PKDrawing? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? PKDrawing(data: data)
        }.value
        if let drawing {
            glyphCache[key] = drawing
        }
        return drawing
    }

    /// Loads every drawn glyph variant of a hand at once (for composing documents).
    func allGlyphs(handID: UUID) async -> [String: [PKDrawing]] {
        guard let hand = hand(id: handID) else { return [:] }
        var result: [String: [PKDrawing]] = [:]
        for character in hand.doneCharacters {
            var variants: [PKDrawing] = []
            for v in 0..<max(1, hand.variantCount(character)) {
                if let drawing = await glyphDrawing(handID: handID, character: character, variant: v) {
                    variants.append(drawing)
                }
            }
            if !variants.isEmpty {
                result[character] = variants
            }
        }
        return result
    }

    func glyphThumbnail(handID: UUID, character: String, side: CGFloat) async -> UIImage? {
        let key = "\(handID.uuidString)-\(character)-\(Int(side))" as NSString
        if let cached = thumbCache.object(forKey: key) { return cached }
        guard let drawing = await glyphDrawing(handID: handID, character: character) else { return nil }
        guard let image = GlyphRenderer.glyphThumbnail(drawing, side: side) else { return nil }
        thumbCache.setObject(image, forKey: key)
        return image
    }

    /// Saves one variant of a captured glyph (already normalized to cell
    /// coordinates). Variant 0 marks the character done; higher variants are
    /// additions.
    func saveGlyph(handID: UUID, character: String, variant: Int, drawing: PKDrawing) async {
        let url = glyphURL(handID, character, variant: variant)
        try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = await Task.detached(priority: .utility) { drawing.dataRepresentation() }.value
        try? data.write(to: url, options: .atomic)
        glyphCache["\(handID.uuidString)-\(character)-\(variant)"] = drawing
        thumbCache.removeObject(forKey: "\(handID.uuidString)-\(character)" as NSString)

        if let idx = hands.firstIndex(where: { $0.id == handID }) {
            if !hands[idx].doneCharacters.contains(character) {
                hands[idx].doneCharacters.append(character)
            }
            hands[idx].skippedCharacters.removeAll { $0 == character }
            hands[idx].variantCounts[character] = max(variant + 1,
                                                      hands[idx].variantCounts[character] ?? 1)
            hands[idx].updatedAt = .now
            persist(hands[idx])
        }
    }

    /// Removes a single variant (falls back to skipping the character when
    /// the last variant is removed).
    func removeGlyphVariant(handID: UUID, character: String, variant: Int) {
        guard let idx = hands.firstIndex(where: { $0.id == handID }) else { return }
        try? fileManager.removeItem(at: glyphURL(handID, character, variant: variant))
        glyphCache["\(handID.uuidString)-\(character)-\(variant)"] = nil

        let remaining = max(0, (hands[idx].variantCounts[character] ?? 1) - (variant >= 0 ? 1 : 0))
        if remaining == 0 {
            hands[idx].doneCharacters.removeAll { $0 == character }
            hands[idx].variantCounts[character] = nil
        } else {
            hands[idx].variantCounts[character] = remaining
        }
        hands[idx].updatedAt = .now
        persist(hands[idx])
    }

    func skipGlyph(handID: UUID, character: String) {
        guard let idx = hands.firstIndex(where: { $0.id == handID }) else { return }
        if !hands[idx].skippedCharacters.contains(character) {
            hands[idx].skippedCharacters.append(character)
        }
        hands[idx].doneCharacters.removeAll { $0 == character }
        hands[idx].variantCounts[character] = nil
        for v in 0...8 {
            try? fileManager.removeItem(at: glyphURL(handID, character, variant: v))
        }
        glyphCache = glyphCache.filter { !$0.key.hasPrefix("\(handID.uuidString)-\(character)-") }
        hands[idx].updatedAt = .now
        persist(hands[idx])
    }

    // MARK: - Helpers

    private func persist(_ hand: HandwritingSet) {
        guard let data = try? JSONEncoder.iso.encode(hand) else { return }
        try? fileManager.createDirectory(at: handURL(hand.id), withIntermediateDirectories: true)
        try? data.write(to: manifestURL(hand.id), options: .atomic)
    }
}

extension JSONDecoder {
    static let iso: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

extension JSONEncoder {
    static let iso: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}
