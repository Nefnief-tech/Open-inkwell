import Foundation
import PencilKit
import UIKit

/// Composes typed text into handwriting strokes and renders pages.
///
/// Glyph coordinate system: every glyph is captured on a full-screen canvas,
/// then normalized on save to a fixed cell height. The baseline is a known
/// fraction of the capture canvas, so after scaling to the cell the baseline
/// sits exactly at `baselineY` — that's what makes vertical placement exact.
enum GlyphRenderer {
    // MARK: - Geometry

    // Cell space (normalized glyph coordinates)
    static let baselineY: CGFloat = 380
    static let xHeightY: CGFloat = 230
    static let ascenderY: CGFloat = 134
    static let descenderY: CGFloat = 476
    static let xHeightSpan: CGFloat = baselineY - xHeightY
    static let cellWidth: CGFloat = 400        // reference width for space width

    /// Baseline-to-baseline distance at scale 1. Tuned so handwriting
    /// captured at comfortable size renders at realistic print size.
    static let naturalLineAdvance: CGFloat = 480

    /// Reference line spacing for "Text size = 1.0". Glyph scale is
    /// independent of the document's line spacing — spacing only positions
    /// baselines, size only scales strokes about them.
    static let naturalLineSpacing: CGFloat = 90

    // Capture-screen metrics in absolute points, anchored to the baseline
    // guide — "write like you normally write" size.
    static let captureXHeight: CGFloat = 70
    static let captureAscender: CGFloat = 115
    static let captureDescender: CGFloat = 45
    static let captureBaselineFraction: CGFloat = 0.58

    /// Maps capture-screen points into cell units (x-height span = 150 units).
    static let captureScale: CGFloat = (baselineY - xHeightY) / captureXHeight

    // MARK: - Composition

    struct ComposeSettings {
        var lineSpacing: CGFloat
        var letterSpacing: CGFloat
        var sizeMultiplier: CGFloat
        var spaceWidthFraction: Double
        var pageWidth: CGFloat
        var leftMargin: CGFloat = 48
        var firstBaseline: CGFloat        // baseline of the first line
        var inkColor: UIColor?            // nil = keep captured colors
        var variationSeed: UInt64 = 0     // + shuffle → re-picks glyph variants
    }

    /// Builds one PKDrawing containing the whole text. Layout is strictly
    /// per-line: every line's baseline is computed absolutely from its index
    /// (`firstBaseline + index * lineSpacing`) with no accumulated vertical
    /// state — glyph scale and line positions are independent by construction.
    /// Undrawn characters are omitted; each occurrence draws a randomly (but
    /// deterministically) picked variation of its glyph.
    static func compose(
        text: String,
        glyphs: [String: [PKDrawing]],
        settings: ComposeSettings
    ) -> PKDrawing {
        // Glyph scale is absolute (anchored to naturalLineSpacing), NOT tied
        // to lineSpacing — changing spacing moves lines, never resizes text.
        let k = (naturalLineSpacing / naturalLineAdvance) * settings.sizeMultiplier
        let spaceAdvance = CGFloat(settings.spaceWidthFraction) * cellWidth * k
        let rightMargin: CGFloat = 48
        let maxWidth = settings.pageWidth - settings.leftMargin - rightMargin

        // 1. Tokenize per paragraph: words, with oversized words split into
        //    character chunks that fit a single line.
        var paragraphs: [[String]] = []
        for paragraph in text.components(separatedBy: "\n") {
            var paragraphTokens: [String] = []
            for word in paragraph.split(separator: " ").map(String.init) {
                var chunk = ""
                var chunkWidth: CGFloat = 0
                for ch in word {
                    let advance = charAdvance(String(ch), glyphs: glyphs, k: k,
                                              letterSpacing: settings.letterSpacing)
                    if !chunk.isEmpty && chunkWidth + advance > maxWidth + 0.5 {
                        paragraphTokens.append(chunk)
                        chunk = ""
                        chunkWidth = 0
                    }
                    chunk += String(ch)
                    chunkWidth += advance
                }
                if !chunk.isEmpty { paragraphTokens.append(chunk) }
            }
            paragraphs.append(paragraphTokens)
        }

        // 2. Word-wrap the tokens into display lines.
        var lines: [[String]] = []
        for paragraphTokens in paragraphs {
            var current: [String] = []
            var currentWidth: CGFloat = 0
            for token in paragraphTokens {
                let w = width(of: token, glyphs: glyphs, k: k,
                              letterSpacing: settings.letterSpacing)
                let needed = current.isEmpty ? w : currentWidth + spaceAdvance + w
                if !current.isEmpty && needed > maxWidth + 0.5 {
                    lines.append(current)
                    current = []
                    currentWidth = 0
                }
                if !current.isEmpty { currentWidth += spaceAdvance }
                current.append(token)
                currentWidth += w
            }
            lines.append(current)
        }

        // 3. Place each line absolutely by its index — the only vertical math.
        var strokes: [PKStroke] = []
        for (lineIndex, lineTokens) in lines.enumerated() {
            let baseline = settings.firstBaseline + CGFloat(lineIndex) * settings.lineSpacing
            if baseline > 20000 { break } // safety for absurd inputs
            var penX = settings.leftMargin
            for (tokenIndex, token) in lineTokens.enumerated() {
                if tokenIndex > 0 { penX += spaceAdvance }
                for ch in token {
                    append(String(ch), glyphs: glyphs, k: k,
                           letterSpacing: settings.letterSpacing,
                           penX: &penX, baseline: baseline,
                           inkColor: settings.inkColor,
                           variationSeed: settings.variationSeed,
                           strokes: &strokes)
                }
            }
        }
        return PKDrawing(strokes: strokes)
    }

    private static func charAdvance(_ character: String, glyphs: [String: [PKDrawing]],
                                    k: CGFloat, letterSpacing: CGFloat) -> CGFloat {
        guard let variants = glyphs[character], let first = variants.first else { return 0 }
        return first.bounds.width * k + letterSpacing
    }

    /// Deterministic per-occurrence variant pick: stable across preview
    /// re-renders, reshuffled by the document's variation seed.
    private static func pickVariant(character: String, occurrence: Int,
                                    count: Int, seed: UInt64) -> Int {
        guard count > 1 else { return 0 }
        var h = UInt64(character.unicodeScalars.first?.value ?? 0) &* 0x9E3779B97F4A7C15
        h ^= UInt64(truncatingIfNeeded: occurrence) &* 0xC2B2AE3D27D4EB4F
        h ^= seed &* 0x165667B19E3779F9
        h ^= h >> 27
        h = h &* 0x94D049BB133111EB
        h ^= h >> 31
        return Int(h % UInt64(count))
    }

    private static func width(of word: String, glyphs: [String: [PKDrawing]], k: CGFloat,
                              letterSpacing: CGFloat) -> CGFloat {
        var w: CGFloat = 0
        for ch in word {
            if let variants = glyphs[String(ch)], let first = variants.first {
                w += first.bounds.width * k + letterSpacing
            }
        }
        return w
    }

    private static func append(_ character: String, glyphs: [String: [PKDrawing]], k: CGFloat,
                               letterSpacing: CGFloat, penX: inout CGFloat, baseline: CGFloat,
                               inkColor: UIColor?, variationSeed: UInt64,
                               strokes: inout [PKStroke]) {
        guard let variants = glyphs[character], !variants.isEmpty else { return }
        let glyph = variants[pickVariant(character: character,
                                         occurrence: strokes.count,
                                         count: variants.count,
                                         seed: variationSeed)]
        let b = glyph.bounds
        let t = CGAffineTransform(
            translationX: penX - b.minX * k,
            y: baseline - baselineY * k
        ).scaledBy(x: k, y: k)
        for stroke in glyph.strokes {
            // Transforms live on PKStroke — concatenate onto its own.
            let totalTransform = stroke.transform.concatenating(t)
            let ink = inkColor.map { PKInk(stroke.ink.inkType, color: $0) } ?? stroke.ink
            strokes.append(PKStroke(ink: ink, path: stroke.path, transform: totalTransform))
        }
        penX += b.width * k + letterSpacing
    }

    // MARK: - Page rendering

    /// Blank-paper page size: A4 proportions, ~150 dpi in points (rendered at
    /// 2-3x on export).
    static let blankPageSize = CGSize(width: 1240, height: 1754)

    static func renderPage(
        size: CGSize,
        scale: CGFloat,
        background: UIImage?,
        template: PaperTemplate,
        composed: PKDrawing
    ) -> UIImage {
        let rect = CGRect(origin: .zero, size: size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = max(1, scale)
        let renderer = UIGraphicsImageRenderer(bounds: rect, format: format)
        return renderer.image { context in
            drawPage(context.cgContext, rect: rect, background: background,
                     template: template, composed: composed, scale: format.scale)
        }
    }

    static func renderPDF(
        size: CGSize,
        background: UIImage?,
        template: PaperTemplate,
        composed: PKDrawing
    ) -> Data {
        let rect = CGRect(origin: .zero, size: size)
        let renderer = UIGraphicsPDFRenderer(bounds: rect)
        return renderer.pdfData { context in
            context.beginPage()
            drawPage(context.cgContext, rect: rect, background: background,
                     template: template, composed: composed, scale: 2)
        }
    }

    private static func drawPage(
        _ cg: CGContext,
        rect: CGRect,
        background: UIImage?,
        template: PaperTemplate,
        composed: PKDrawing,
        scale: CGFloat
    ) {
        if let background {
            background.draw(in: rect)
        } else {
            cg.setFillColor(PaperTheme.uiPaper.cgColor)
            cg.fill(rect)
            template.draw(in: cg, rect: rect, color: PaperTheme.uiLine)
        }
        composed.image(from: rect, scale: scale).draw(in: rect)
    }

    // MARK: - Glyph helpers

    /// Normalizes a capture-canvas drawing into cell coordinates: scales by
    /// the x-height ratio AND translates so the capture baseline (a known
    /// fraction of the canvas height) lands exactly on `baselineY`. Without
    /// the translation every glyph would carry a large downward offset that
    /// grows with the render scale.
    static func normalize(_ drawing: PKDrawing, captureHeight: CGFloat) -> PKDrawing {
        guard !drawing.strokes.isEmpty else { return drawing }
        let height = captureHeight > 0 ? captureHeight : 1000
        let baselineScreen = height * captureBaselineFraction
        let t = CGAffineTransform(translationX: 0, y: baselineY)
            .scaledBy(x: captureScale, y: captureScale)
            .translatedBy(x: 0, y: -baselineScreen)
        return drawing.transformed(using: t)
    }

    /// Small preview image of a single glyph (for the progress grid).
    static func glyphThumbnail(_ drawing: PKDrawing, side: CGFloat) -> UIImage? {
        let bounds = drawing.bounds
        guard !bounds.isEmpty else { return nil }
        let padded = bounds.insetBy(dx: -18, dy: -18)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let renderer = UIGraphicsImageRenderer(
            bounds: CGRect(origin: .zero, size: CGSize(width: side, height: side)),
            format: format
        )
        return renderer.image { _ in
            drawing.image(from: padded, scale: format.scale)
                .draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
    }

    // MARK: - Umlaut auto-generation

    /// Base character used for auto-generating umlauts.
    static func umlautBase(for character: String) -> String? {
        switch character {
        case "Ä": return "A"
        case "Ö": return "O"
        case "Ü": return "U"
        case "ä": return "a"
        case "ö": return "o"
        case "ü": return "u"
        default: return nil
        }
    }

    /// Copies the base glyph and stamps two dots above it.
    static func addUmlautDots(to drawing: PKDrawing) -> PKDrawing {
        let b = drawing.bounds
        guard !b.isEmpty else { return drawing }
        let dotRadius: CGFloat = 9
        let gap: CGFloat = 26
        let offsetX: CGFloat = dotRadius + 10
        let cy = b.minY - gap

        func dot(_ x: CGFloat, _ y: CGFloat) -> PKStroke {
            let point = PKStrokePoint(
                location: CGPoint(x: x, y: y),
                timeOffset: 0,
                size: CGSize(width: dotRadius * 2, height: dotRadius * 2),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
            return PKStroke(
                ink: PKInk(.pen, color: .black),
                path: PKStrokePath(controlPoints: [point], creationDate: Date())
            )
        }

        return PKDrawing(strokes: drawing.strokes + [
            dot(b.midX - offsetX, cy),
            dot(b.midX + offsetX, cy),
        ])
    }
}
