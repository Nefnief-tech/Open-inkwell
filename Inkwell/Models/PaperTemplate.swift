import UIKit

/// Paper templates rendered as a background layer under the drawing.
enum PaperTemplate: String, Codable, CaseIterable, Hashable {
    case plain, lined, grid, dots

    var displayName: String {
        switch self {
        case .plain: return "Plain"
        case .lined: return "Lined"
        case .grid: return "Grid"
        case .dots: return "Dotted"
        }
    }

    var systemImage: String {
        switch self {
        case .plain: return "rectangle"
        case .lined: return "text.alignleft"
        case .grid: return "grid"
        case .dots: return "circle.grid.3x3"
        }
    }

    static let spacing: CGFloat = 28

    /// Draws the template into a CGContext (used both by the live paper view
    /// and by thumbnail generation).
    func draw(in ctx: CGContext, rect: CGRect, color: UIColor) {
        guard self != .plain else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }
        let s = Self.spacing
        ctx.setStrokeColor(color.cgColor)
        ctx.setFillColor(color.cgColor)
        ctx.setLineWidth(1)

        switch self {
        case .plain:
            break
        case .lined:
            var y = rect.minY + s
            while y <= rect.maxY - 4 {
                ctx.move(to: CGPoint(x: rect.minX + 8, y: y))
                ctx.addLine(to: CGPoint(x: rect.maxX - 8, y: y))
                y += s
            }
            ctx.strokePath()
        case .grid:
            var y = rect.minY + s
            while y <= rect.maxY - 4 {
                ctx.move(to: CGPoint(x: rect.minX + 8, y: y))
                ctx.addLine(to: CGPoint(x: rect.maxX - 8, y: y))
                y += s
            }
            var x = rect.minX + s
            while x <= rect.maxX - 4 {
                ctx.move(to: CGPoint(x: x, y: rect.minY + 8))
                ctx.addLine(to: CGPoint(x: x, y: rect.maxY - 8))
                x += s
            }
            ctx.strokePath()
        case .dots:
            let r: CGFloat = 1.6
            var y = rect.minY + s
            while y <= rect.maxY - 4 {
                var x = rect.minX + s
                while x <= rect.maxX - 4 {
                    ctx.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                    x += s
                }
                y += s
            }
            ctx.fillPath()
        }
    }
}
