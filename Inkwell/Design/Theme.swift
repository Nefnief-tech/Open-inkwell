import SwiftUI
import UIKit

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

/// Ink swatches + stroke widths shared by the custom tool block.
enum InkPalette {
    static let colors: [Color] = [
        Color(hex: 0x1C1B1F), // black
        Color(hex: 0x7A7D85), // graphite
        Color(hex: 0xE5484D), // red
        Color(hex: 0xF76B15), // orange
        Color(hex: 0x30A46C), // green
        Color(hex: 0x0090FF), // blue
        Color(hex: 0x6E56CF), // purple
        Color(hex: 0xAD7F58), // brown
    ]
    static let uiColors: [UIColor] = colors.map { UIColor($0) }
    static let widths: [CGFloat] = [3, 6, 12]
}

/// Cover color themes for notebooks (GoodNotes-style).
struct CoverTheme: Identifiable, Hashable {
    let id: Int
    let name: String
    let light: Color
    let dark: Color

    init(id: Int, name: String, light: UInt32, dark: UInt32) {
        self.id = id
        self.name = name
        self.light = Color(hex: light)
        self.dark = Color(hex: dark)
    }
}

enum CoverPalette {
    static let themes: [CoverTheme] = [
        CoverTheme(id: 0, name: "Indigo", light: 0x6E78F0, dark: 0x3A3F8F),
        CoverTheme(id: 1, name: "Ocean", light: 0x3B82C4, dark: 0x1E4E7A),
        CoverTheme(id: 2, name: "Teal", light: 0x2FA8A0, dark: 0x18635F),
        CoverTheme(id: 3, name: "Forest", light: 0x4C9F62, dark: 0x2A5D3A),
        CoverTheme(id: 4, name: "Amber", light: 0xE0A83A, dark: 0x8F6A1D),
        CoverTheme(id: 5, name: "Coral", light: 0xE56B5D, dark: 0x93392F),
        CoverTheme(id: 6, name: "Rose", light: 0xD3649E, dark: 0x8A3A66),
        CoverTheme(id: 7, name: "Slate", light: 0x64707E, dark: 0x39414C),
    ]

    static func theme(_ index: Int) -> CoverTheme {
        let count = themes.count
        return themes[((index % count) + count) % count]
    }
}

/// Shared paper appearance. The page is always warm cream (in both light and
/// dark chrome) so ink colors stay predictable — same approach as paper apps.
enum PaperTheme {
    static let uiPaper = UIColor(red: 253 / 255, green: 251 / 255, blue: 244 / 255, alpha: 1)
    static let uiLine = UIColor(red: 0.82, green: 0.79, blue: 0.72, alpha: 1)
}
