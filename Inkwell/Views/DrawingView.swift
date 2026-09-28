import SwiftUI
import PencilKit

/// Full-bleed drawing surface backed by PKCanvasView + PKToolPicker.
///
/// Pencil behavior on iPad (10th gen) + Apple Pencil (USB-C):
/// - Palm rejection and input de-duplication are handled by PencilKit/iPadOS.
/// - Tilt is honored by the marker/watercolor inks. There is no pressure
///   sensor on the USB-C Pencil, so stroke width is fixed per tool setting.
struct DrawingView: View {
    let notebookID: UUID
    let page: PageInfo

    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("fingerDrawing") private var fingerDrawing = true

    @State private var drawing = PKDrawing()
    @State private var editVersion = 0
    @State private var canvasSize: CGSize = .zero
    @State private var saveTask: Task<Void, Never>?
    @State private var confirmingDelete = false

    private var pageTitle: String {
        let notebook = library.notebook(id: notebookID)
        let index = notebook?.pages.firstIndex { $0.id == page.id } ?? 0
        return "Page \(index + 1)"
    }

    var body: some View {
        GeometryReader { geo in
            PencilCanvasView(
                drawing: drawing,
                editVersion: editVersion,
                fingerDrawing: fingerDrawing,
                onDrawingChanged: handleDrawingChanged
            )
            .background(Color(uiColor: .systemBackground))
            .onAppear { canvasSize = geo.size }
            .onChange(of: geo.size) { _, newSize in
                canvasSize = newSize
            }
        }
        .ignoresSafeArea(edges: .bottom)
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
        Task {
            await library.savePageDrawing(
                notebookID: notebookID,
                pageID: page.id,
                drawing: snapshot,
                pageSize: size,
                scale: scale
            )
        }
    }
}

// MARK: - UIViewRepresentable bridge

private struct PencilCanvasView: UIViewRepresentable {
    var drawing: PKDrawing
    var editVersion: Int
    var fingerDrawing: Bool
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
        view.drawing = drawing

        let picker = context.coordinator.toolPicker
        picker.addObserver(view)
        picker.setVisible(true, forFirstResponder: view)
        DispatchQueue.main.async {
            view.becomeFirstResponder()
        }
        return view
    }

    func updateUIView(_ view: PKCanvasView, context: Context) {
        if context.coordinator.lastAppliedFingerDrawing != fingerDrawing {
            context.coordinator.lastAppliedFingerDrawing = fingerDrawing
            view.drawingPolicy = fingerDrawing ? .anyInput : .pencilOnly
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
        let toolPicker = PKToolPicker()
        var lastAppliedEditVersion = 0
        var lastAppliedFingerDrawing: Bool

        private let onDrawingChanged: (PKDrawing) -> Void

        init(onDrawingChanged: @escaping (PKDrawing) -> Void, fingerDrawing: Bool) {
            self.onDrawingChanged = onDrawingChanged
            self.lastAppliedFingerDrawing = fingerDrawing
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            onDrawingChanged(canvasView.drawing)
        }
    }
}
