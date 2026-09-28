import SwiftUI
import PencilKit

/// Full-bleed drawing surface: cream paper with a template layer under a
/// transparent PKCanvasView, plus the custom floating tool block.
///
/// Pencil behavior on iPad (10th gen) + Apple Pencil (USB-C):
/// - Palm rejection and input de-duplication are handled by PencilKit/iPadOS.
/// - Tilt is honored by the pencil/marker inks. There is no pressure sensor
///   on the USB-C Pencil, so stroke width is set per tool.
struct DrawingView: View {
    let notebookID: UUID
    let page: PageInfo

    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("fingerDrawing") private var fingerDrawing = true

    @AppStorage("toolKind") private var toolKindRaw = ToolKind.pen.rawValue
    @AppStorage("toolColor") private var toolColor = 0
    @AppStorage("toolWidth") private var toolWidth = 1

    @State private var drawing = PKDrawing()
    @State private var editVersion = 0
    @State private var canvasSize: CGSize = .zero
    @State private var saveTask: Task<Void, Never>?
    @State private var confirmingDelete = false
    @State private var showToolBlock = true
    @State private var controller = CanvasController()

    private var toolBinding: Binding<ToolConfig> {
        Binding(
            get: {
                ToolConfig(kind: ToolKind(rawValue: toolKindRaw) ?? .pen,
                           colorIndex: toolColor,
                           widthIndex: toolWidth)
            },
            set: {
                toolKindRaw = $0.kind.rawValue
                toolColor = $0.colorIndex
                toolWidth = $0.widthIndex
            }
        )
    }

    private var template: PaperTemplate {
        let notebook = library.notebook(id: notebookID)
        let livePage = notebook?.pages.first { $0.id == page.id }
        return livePage?.template ?? notebook?.template ?? .plain
    }

    private var pageTitle: String {
        let notebook = library.notebook(id: notebookID)
        let index = notebook?.pages.firstIndex { $0.id == page.id } ?? 0
        return "Page \(index + 1)"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { geo in
                PencilCanvasView(
                    drawing: drawing,
                    editVersion: editVersion,
                    toolConfig: toolBinding.wrappedValue,
                    fingerDrawing: fingerDrawing,
                    controller: controller,
                    onDrawingChanged: handleDrawingChanged
                )
                .background(PaperBackground(template: template))
                .onAppear { canvasSize = geo.size }
                .onChange(of: geo.size) { _, newSize in
                    canvasSize = newSize
                }
            }
            .ignoresSafeArea(edges: .bottom)

            if showToolBlock {
                ToolBlock(config: toolBinding, controller: controller) {
                    showToolBlock = false
                }
                .padding(.bottom, 12)
            } else {
                Button {
                    showToolBlock = true
                } label: {
                    Image(systemName: "paintbrush.pointed.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(13)
                        .background(.regularMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(.quaternary))
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 12)
                .accessibilityLabel("Show Tools")
            }
        }
        .navigationTitle(pageTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    confirmingDelete = true
                } label: {
                    Label("Delete Page", systemImage: "trash")
                }
            }
        }
        .confirmationDialog(
            "Delete this page? This cannot be undone.",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Page", role: .destructive) {
                library.deletePage(page.id, in: notebookID)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
        .task(id: page.id) {
            let loaded = await library.loadDrawing(notebookID: notebookID, pageID: page.id)
            drawing = loaded
            editVersion += 1
        }
        .onDisappear {
            flushSave()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                flushSave()
            }
        }
    }

    private func handleDrawingChanged(_ newDrawing: PKDrawing) {
        drawing = newDrawing
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            flushSave()
        }
    }

    private func flushSave() {
        saveTask?.cancel()
        let snapshot = drawing
        let size = canvasSize
        let scale = displayScale
        let paperTemplate = template
        Task {
            await library.savePageDrawing(
                notebookID: notebookID,
                pageID: page.id,
                drawing: snapshot,
                pageSize: size,
                scale: scale,
                template: paperTemplate
            )
        }
    }
}

// MARK: - UIViewRepresentable bridge

private struct PencilCanvasView: UIViewRepresentable {
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
        // Only push drawing data into the canvas when we loaded a page from
        // disk (editVersion bumps). Changes made by the user flow out through
        // the delegate and must never be echoed back in.
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

// MARK: - Paper background

/// Cream paper with the template pattern drawn in -draw(rect:), living under
/// the transparent canvas. Handles size and template changes itself.
private final class PaperView: UIView {
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

private struct PaperBackground: UIViewRepresentable {
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
