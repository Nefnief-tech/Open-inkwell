import Foundation

/// The character groups offered during guided capture. Users draw what they
/// need and skip the rest — every group is optional, as is every character.
enum CharsetGroup: String, CaseIterable, Identifiable, Hashable {
    case uppercase, lowercase, digits, german, punctuation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .uppercase: return "Uppercase"
        case .lowercase: return "Lowercase"
        case .digits: return "Digits"
        case .german: return "German"
        case .punctuation: return "Signs"
        }
    }

    var systemImage: String {
        switch self {
        case .uppercase: return "textformat"
        case .lowercase: return "textformat.size.smaller"
        case .digits: return "number"
        case .german: return "globe"
        case .punctuation: return "questionmark.quote"
        }
    }

    var characters: [String] {
        switch self {
        case .uppercase:
            return (65...90).compactMap { UnicodeScalar($0).map(String.init) }
        case .lowercase:
            return (97...122).compactMap { UnicodeScalar($0).map(String.init) }
        case .digits:
            return ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
        case .german:
            return ["Ä", "Ö", "Ü", "ä", "ö", "ü", "ß"]
        case .punctuation:
            return [".", ",", "!", "?", ":", ";", "'", "\"", "-", "–",
                    "(", ")", "@", "&", "/", "+", "=", "*", "#", "%", "€"]
        }
    }

    /// Ordered master list used for the auto-advance capture flow.
    static var allCharacters: [String] {
        CharsetGroup.allCases.flatMap { $0.characters }
    }

    static func group(of character: String) -> CharsetGroup? {
        CharsetGroup.allCases.first { $0.characters.contains(character) }
    }
}

/// A user handwriting ("hand"): metadata + which characters are drawn/skipped
/// and how many variations each character has. Glyph stroke data lives in
/// `glyphs/<unicode-hex>.drawing` (variant 0) and `glyphs/<hex>-v<n>.drawing`
/// (variants ≥ 1) next to hand.json.
struct HandwritingSet: Identifiable, Hashable {
    let id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var spaceWidth: Double = 0.35          // fraction of glyph cell width
    var doneCharacters: [String] = []
    var skippedCharacters: [String] = []
    var variantCounts: [String: Int] = [:] // per character; defaults to 1 when done
    var geometryVersion: Int = 1           // 0 = captured before baseline anchoring fix

    var doneCount: Int { doneCharacters.count }
    var totalCount: Int { CharsetGroup.allCharacters.count }

    func isDone(_ character: String) -> Bool { doneCharacters.contains(character) }
    func isSkipped(_ character: String) -> Bool { skippedCharacters.contains(character) }
    func variantCount(_ character: String) -> Int {
        variantCounts[character] ?? (isDone(character) ? 1 : 0)
    }
}

extension HandwritingSet: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, createdAt, updatedAt, spaceWidth
        case doneCharacters, skippedCharacters, variantCounts, geometryVersion
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        spaceWidth = try c.decodeIfPresent(Double.self, forKey: .spaceWidth) ?? 0.35
        doneCharacters = try c.decodeIfPresent([String].self, forKey: .doneCharacters) ?? []
        skippedCharacters = try c.decodeIfPresent([String].self, forKey: .skippedCharacters) ?? []
        variantCounts = try c.decodeIfPresent([String: Int].self, forKey: .variantCounts) ?? [:]
        geometryVersion = try c.decodeIfPresent(Int.self, forKey: .geometryVersion) ?? 0
    }
}

/// A rendered output: typed text in a chosen hand, on a background.
struct HandDocument: Identifiable, Hashable {
    let id: UUID
    var name: String
    var handID: UUID
    var text: String = ""
    var usesBackgroundImage: Bool = false
    var template: PaperTemplate = .lined    // used when no background image
    var lineSpacing: Double = 90            // baseline-to-baseline, points
    var letterSpacing: Double = 2
    var sizeMultiplier: Double = 1
    var inkColorIndex: Int = 0
    var leftMargin: Double = 48             // "line start"
    var firstBaseline: Double = 90          // baseline of the first line from top
    var variationSeed: Int = 0              // + shuffle → re-picks glyph variants
    var layoutVersion: Int = 1              // 1 = size decoupled from spacing
    var snapToRuling: Bool = false          // place lines on detected ruling
    var rulingBaselines: [Double]? = nil    // detected paper line positions (page points)
    var createdAt: Date
    var updatedAt: Date
}

extension HandDocument: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, handID, text, usesBackgroundImage, template
        case lineSpacing, letterSpacing, sizeMultiplier, inkColorIndex
        case leftMargin, firstBaseline, variationSeed, layoutVersion
        case snapToRuling, rulingBaselines, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        handID = try c.decode(UUID.self, forKey: .handID)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        usesBackgroundImage = try c.decodeIfPresent(Bool.self, forKey: .usesBackgroundImage) ?? false
        template = try c.decodeIfPresent(PaperTemplate.self, forKey: .template) ?? .lined
        lineSpacing = try c.decodeIfPresent(Double.self, forKey: .lineSpacing) ?? 90
        letterSpacing = try c.decodeIfPresent(Double.self, forKey: .letterSpacing) ?? 2
        sizeMultiplier = try c.decodeIfPresent(Double.self, forKey: .sizeMultiplier) ?? 1
        inkColorIndex = try c.decodeIfPresent(Int.self, forKey: .inkColorIndex) ?? 0
        leftMargin = try c.decodeIfPresent(Double.self, forKey: .leftMargin) ?? 48
        firstBaseline = try c.decodeIfPresent(Double.self, forKey: .firstBaseline) ?? 90
        variationSeed = try c.decodeIfPresent(Int.self, forKey: .variationSeed) ?? 0
        layoutVersion = try c.decodeIfPresent(Int.self, forKey: .layoutVersion) ?? 0
        snapToRuling = try c.decodeIfPresent(Bool.self, forKey: .snapToRuling) ?? false
        rulingBaselines = try c.decodeIfPresent([Double].self, forKey: .rulingBaselines)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }
}
