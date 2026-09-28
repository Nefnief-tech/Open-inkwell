import SwiftUI
import PencilKit

/// Guided character capture: full-screen canvas with handwriting guides, a
/// faint reference letter, and auto-advance. Reachable as a sheet from the
/// hand detail grid.
struct GlyphCaptureView: View {
    let handID: UUID
    let characters: [String]          // ordered capture list
    @Binding var index: Int?          // nil = sheet closed
    let onFinished: () -> Void

    @Environment(HandStore.self) private var hands
    @Environment(\.dismiss) private var dismiss
    @AppStorage("fingerDrawing") private var fingerDrawing = true
    @AppStorage("toolKind") private var toolKindRaw = ToolKind.pen.rawValue
    @AppStorage("toolColor") private var toolColor = 0
    @AppStorage("toolWidth") private var toolWidth = 1

    @State private var drawing = PKDrawing()
    @State private var editVersion = 0
    @State private var canvasSize: CGSize = .zero
    @State private var controller = CanvasController()
    @State private var isSaving = false

    private var character: String? {
        guard let index, characters.indices.contains(index) else { return nil }
        return characters[index]
    }

    private var toolBinding: Binding<ToolConfig> {
        Binding(
            get: {
                ToolConfig(kind: ToolKind(rawValue: toolKindRaw) ?? .pen,
                           colorIndex: toolColor, widthIndex: toolWidth)
            },
            set: {
                toolKindRaw = $0.kind.rawValue
                toolColor = $0.colorIndex
                toolWidth = $0.widthIndex
            }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                GeometryReader { geo in
                    ZStack {
                        GuideOverlay()
                        Text(character ?? " ")
                            .font(.system(size: geo.size.height * 0.55, weight: .light))
                            .foregroundStyle(Color.primary.opacity(0.07))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        PencilCanvasView(
                            drawing: drawing,
                            editVersion: editVersion,
                            toolConfig: toolBinding.wrappedValue,
                            fingerDrawing: fingerDrawing,
                            controller: controller,
                            onDrawingChanged: { drawing = $0 }
                        )
                    }
                    .onAppear { canvasSize = geo.size }
                }
                .ignoresSafeArea(edges: .bottom)

                ToolBlock(config: toolBinding, controller: controller) {}
                    .padding(.bottom, 8)
            }
            .background(PaperTheme.uiPaper.color)
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItemGroup {
                    Button {
                        drawing = PKDrawing()
                        editVersion += 1
                    } label: {
                        Label("Clear", systemImage: "arrow.counterclockwise")
                    }
                    Button {
                        markSkipped()
                    } label: {
                        Label("Skip", systemImage: "forward.end")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        saveAndAdvance()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save ✓")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(isSaving || character == nil)
                }
            }
            .safeAreaInset(edge: .bottom) {
                umlautShortcut
            }
            .task(id: character) {
                await loadCurrent()
            }
        }
    }

    private var titleText: String {
        guard let index, let character else { return "" }
        return "“\(character)” · \(index + 1)/\(characters.count)"
    }

    /// One-tap umlauts: copy the base letter's glyph and stamp two dots.
    @ViewBuilder
    private var umlautShortcut: some View {
        if let character, let base = GlyphRenderer.umlautBase(for: character) {
            let baseDrawn = hands.hand(id: handID)?.isDone(base) ?? false
            let label = Label(
                baseDrawn ? "Auto-build from “\(base)”" : "Draw “\(base)” first to auto-build",
                systemImage: "wand.and.stars"
            )
            Group {
                if baseDrawn {
                    Button {
                        generateFromBase(base)
                    } label: {
                        label
                            .font(.callout.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        generateFromBase(base)
                    } label: {
                        label
                            .font(.callout)
                    }
                    .buttonStyle(.bordered)
                    .disabled(true)
                }
            }
            .padding(.bottom, 4)
        }
    }

    private func loadCurrent() async {
        guard let character, let hand = hands.hand(id: handID) else { return }
        if hand.isDone(character) {
            drawing = await hands.glyphDrawing(handID: handID, character: character) ?? PKDrawing()
        } else {
            drawing = PKDrawing()
        }
        editVersion += 1
    }

    private func generateFromBase(_ base: String) {
        guard let character else { return }
        isSaving = true
        Task {
            if let baseDrawing = await hands.glyphDrawing(handID: handID, character: base) {
                let combined = GlyphRenderer.addUmlautDots(to: baseDrawing)
                drawing = combined
                editVersion += 1
                await hands.saveGlyph(handID: handID, character: character, drawing: combined)
                advance()
            }
            isSaving = false
        }
    }

    private func saveAndAdvance() {
        guard let character else { return }
        isSaving = true
        let normalized = GlyphRenderer.normalize(drawing, captureHeight: canvasSize.height)
        let handID = self.handID
        let store = hands
        Task {
            await store.saveGlyph(handID: handID, character: character, drawing: normalized)
            isSaving = false
            advance()
        }
    }

    private func markSkipped() {
        guard let character else { return }
        hands.skipGlyph(handID: handID, character: character)
        advance()
    }

    private func advance() {
        guard let index else { return }
        if index + 1 < characters.count {
            self.index = index + 1
        } else {
            onFinished()
            dismiss()
        }
    }
}

/// Dashed guides matching GlyphRenderer's capture geometry (fractions of the
/// capture canvas height). Baseline is the anchor for all rendering.
struct GuideOverlay: View {
    private struct Guide: Identifiable {
        let name: String
        let fraction: CGFloat
        var id: String { name }
    }

    private var guides: [Guide] {
        [
            Guide(name: "Ascender", fraction: GlyphRenderer.ascenderY / GlyphRenderer.captureCellHeight),
            Guide(name: "x-height", fraction: GlyphRenderer.xHeightY / GlyphRenderer.captureCellHeight),
            Guide(name: "Baseline", fraction: GlyphRenderer.baselineY / GlyphRenderer.captureCellHeight),
            Guide(name: "Descender", fraction: GlyphRenderer.descenderY / GlyphRenderer.captureCellHeight),
        ]
    }

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                for guide in guides {
                    let y = guide.fraction * size.height
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(
                        path,
                        with: .color(Color(red: 0.85, green: 0.3, blue: 0.35).opacity(0.4)),
                        style: StrokeStyle(lineWidth: 1, dash: [6, 5])
                    )
                    context.draw(
                        Text(guide.name).font(.caption2).foregroundStyle(.secondary),
                        at: CGPoint(x: size.width - 52, y: y - 9)
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}
