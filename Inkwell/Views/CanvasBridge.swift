import SwiftUI
import PencilKit

/// Shared PKCanvasView bridge used by the glyph capture screen.
///
/// The caller owns the drawing value; changes flow out via `onDrawingChanged`
/// and are only pushed back in on `editVersion` bumps (page loads).
struct PencilCanvasView: UIViewRepresentable {
    var drawing: PKDrawing
    var editVersion: Int
    var toolConfig: ToolConfig
    var fingerDrawing: Bool
    var controller: CanvasController
    var onDrawingChanged: (PKDrawing) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDrawingChanged: onDrawingChanged, fingerDrawing: fingerDrawing)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let view = PKCanvasView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.delegate = context.coordinator
        view.drawingPolicy = fingerDrawing ? .anyInput : .pencilOnly

        context.coordinator.lastAppliedEditVersion = editVersion
        context.coordinator.lastAppliedToolConfig = toolConfig
        controller.canvas = view
        view.tool = toolConfig.pkTool
        view.drawing = drawing
        return view
    }

    func updateUIView(_ view: PKCanvasView, context: Context) {
        if context.coordinator.lastAppliedFingerDrawing != fingerDrawing {
            context.coordinator.lastAppliedFingerDrawing = fingerDrawing
            view.drawingPolicy = fingerDrawing ? .anyInput : .pencilOnly
        }
        if context.coordinator.lastAppliedToolConfig != toolConfig {
            context.coordinator.lastAppliedToolConfig = toolConfig
            view.tool = toolConfig.pkTool
        }
        if context.coordinator.lastAppliedEditVersion != editVersion {
            context.coordinator.lastAppliedEditVersion = editVersion
            view.drawing = drawing
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var lastAppliedEditVersion = 0
        var lastAppliedFingerDrawing: Bool
        var lastAppliedToolConfig: ToolConfig

        private let onDrawingChanged: (PKDrawing) -> Void

        init(onDrawingChanged: @escaping (PKDrawing) -> Void, fingerDrawing: Bool) {
            self.onDrawingChanged = onDrawingChanged
            self.lastAppliedFingerDrawing = fingerDrawing
            self.lastAppliedToolConfig = ToolConfig()
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            onDrawingChanged(canvasView.drawing)
        }
    }
}

/// Cream paper view with template lines (blank document backgrounds).
final class PaperView: UIView {
    var template: PaperTemplate = .plain {
        didSet {
            if template != oldValue { setNeedsDisplay() }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = PaperTheme.uiPaper
        isOpaque = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        template.draw(in: ctx, rect: bounds, color: PaperTheme.uiLine)
    }
}

struct PaperBackground: UIViewRepresentable {
    let template: PaperTemplate

    func makeUIView(context: Context) -> PaperView {
        let view = PaperView()
        view.template = template
        return view
    }

    func updateUIView(_ view: PaperView, context: Context) {
        view.template = template
    }
}

extension UIColor {
    var color: Color { Color(self) }
}
