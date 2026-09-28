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
    // MARK: - Capture geometry (must match GlyphCaptureView's guides)

    static let captureCellHeight: CGFloat = 560
    static let baselineY: CGFloat = 380        // in cell units
    static let ascenderY: CGFloat = 110
    static let xHeightY: CGFloat = 230
    static let descenderY: CGFloat = 500
    static let cellWidth: CGFloat = 400        // reference width for space width

    /// Baseline-to-baseline distance at scale 1.
    static let naturalLineAdvance: CGFloat = 120

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
    }

    /// Builds one PKDrawing containing the whole text laid out on the line
    /// grid. Undrawn characters are omitted.
    static func compose(
        text: String,
        glyphs: [String: PKDrawing],
        settings: ComposeSettings
    ) -> PKDrawing {
        let k = (settings.lineSpacing / naturalLineAdvance) * settings.sizeMultiplier
        let spaceAdvance = CGFloat(settings.spaceWidthFraction) * cellWidth * k
        let maxWidth = settings.pageWidth - settings.leftMargin * 2

        var strokes: [PKStroke] = []
        var baseline = settings.firstBaseline

        for paragraph in text.components(separatedBy: "\n") {
            var penX = settings.leftMargin
            var lineIsEmpty = true

            let words = paragraph.split(separator: " ", omittingEmptySubsequences: false)
            for word in words {
                let wordWidth = width(of: String(word), glyphs: glyphs, k: k,
                                      letterSpacing: settings.letterSpacing)
                if !lineIsEmpty && penX + spaceAdvance + wordWidth > maxWidth + 0.5 {
                    // wrap to next line
                    baseline += settings.lineSpacing
                    penX = settings.leftMargin
                    lineIsEmpty = true
                }
                if !lineIsEmpty {
                    penX += spaceAdvance
                }
                for ch in word {
                    append(String(ch), glyphs: glyphs, k: k,
                           letterSpacing: settings.letterSpacing,
                           penX: &penX, baseline: baseline,
                           inkColor: settings.inkColor, strokes: &strokes)
                }
                lineIsEmpty = false
                // hard-break a single word that can't fit on a line at all
                if penX > maxWidth + settings.leftMargin {
                    baseline += settings.lineSpacing
                    penX = settings.leftMargin
                }
            }
            baseline += settings.lineSpacing
            if baseline > 20000 { break } // safety for absurd inputs
        }
        return PKDrawing(strokes: strokes)
    }

    private static func width(of word: String, glyphs: [String: PKDrawing], k: CGFloat,
                              letterSpacing: CGFloat) -> CGFloat {
        var w: CGFloat = 0
        for ch in word {
            if let g = glyphs[String(ch)], !g.strokes.isEmpty {
                w += g.bounds.width * k + letterSpacing
            }
        }
        return w
    }

    private static func append(_ character: String, glyphs: [String: PKDrawing], k: CGFloat,
                               letterSpacing: CGFloat, penX: inout CGFloat, baseline: CGFloat,
                               inkColor: UIColor?, strokes: inout [PKStroke]) {
        guard let glyph = glyphs[character], !glyph.strokes.isEmpty else { return }
        let b = glyph.bounds
        let t = CGAffineTransform(
            translationX: penX - b.minX * k,
            y: baseline - baselineY * k
        ).scaledBy(x: k, y: k)
        for stroke in glyph.strokes {
            let transformed = stroke.transformed(using: t)
            if let inkColor {
                strokes.append(PKStroke(path: transformed.path,
                                        ink: PKInk(transformed.ink.inkType, color: inkColor)))
            } else {
                strokes.append(transformed)
            }
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

    /// Normalizes a capture-canvas drawing into cell coordinates so the
    /// baseline always lands on `baselineY`.
    static func normalize(_ drawing: PKDrawing, captureHeight: CGFloat) -> PKDrawing {
        guard captureHeight > 0, !drawing.strokes.isEmpty else { return drawing }
        let s = captureCellHeight / captureHeight
        return drawing.transformed(using: CGAffineTransform(scaleX: s, y: s))
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
            return PKStroke(path: PKStrokePath(points: [point], creationDate: Date()),
                            ink: PKInk(.pen, color: .black))
        }

        return PKDrawing(strokes: drawing.strokes + [
            dot(b.midX - offsetX, cy),
            dot(b.midX + offsetX, cy),
        ])
    }
}
