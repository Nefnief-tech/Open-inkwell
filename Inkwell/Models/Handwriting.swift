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

/// A user handwriting ("hand"): metadata + which characters are drawn/skipped.
/// Glyph stroke data lives in `glyphs/<unicode-hex>.drawing` next to hand.json.
struct HandwritingSet: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var spaceWidth: Double = 0.35          // fraction of glyph cell width
    var doneCharacters: [String] = []
    var skippedCharacters: [String] = []

    var doneCount: Int { doneCharacters.count }
    var totalCount: Int { CharsetGroup.allCharacters.count }

    func isDone(_ character: String) -> Bool { doneCharacters.contains(character) }
    func isSkipped(_ character: String) -> Bool { skippedCharacters.contains(character) }
}

/// A rendered output: typed text in a chosen hand, on a background.
struct HandDocument: Identifiable, Hashable, Codable {
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
    var createdAt: Date
    var updatedAt: Date
}
