import SwiftUI
import PencilKit
import UIKit

/// Guided character capture: full-screen canvas with handwriting guides at
/// natural writing size, plus a font-metric-anchored reference glyph in the
/// background that doubles as a size reference. Auto-advances on save.
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
                ZStack {
                    GuideOverlay()
                    ReferenceGlyphView(character: character ?? " ")
                    PencilCanvasView(
                        drawing: drawing,
                        editVersion: editVersion,
                        toolConfig: toolBinding.wrappedValue,
                        fingerDrawing: fingerDrawing,
                        controller: controller,
                        onDrawingChanged: { drawing = $0 }
                    )
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
        let normalized = GlyphRenderer.normalize(drawing)
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

/// Dashed guides at absolute point offsets from the baseline (natural
/// writing size). The baseline sits at `captureBaselineFraction` of height.
struct GuideOverlay: View {
    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let baseline = size.height * GlyphRenderer.captureBaselineFraction
                let lines: [(name: String, offset: CGFloat)] = [
                    ("Ascender", GlyphRenderer.captureAscender),
                    ("x-height", GlyphRenderer.captureXHeight),
                    ("Baseline", 0),
                    ("Descender", -GlyphRenderer.captureDescender),
                ]
                for line in lines {
                    let y = baseline - line.offset
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(
                        path,
                        with: .color(Color(red: 0.85, green: 0.3, blue: 0.35).opacity(0.4)),
                        style: StrokeStyle(lineWidth: 1, dash: [6, 5])
                    )
                    context.draw(
                        Text(line.name).font(.caption2).foregroundStyle(.secondary),
                        at: CGPoint(x: size.width - 52, y: y - 9)
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Reference glyph (size reference)

/// Shows the character in the background at natural writing size, with its
/// font baseline exactly on the baseline guide — a real size reference.
struct ReferenceGlyphView: UIViewRepresentable {
    let character: String

    func makeUIView(context: Context) -> ReferenceGlyphLabel {
        ReferenceGlyphLabel()
    }

    func updateUIView(_ view: ReferenceGlyphLabel, context: Context) {
        view.character = character
    }
}

final class ReferenceGlyphLabel: UIView {
    private let label = UILabel()

    var character: String = "" {
        didSet {
            if character != oldValue { setNeedsLayout() }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.textAlignment = .center
        label.textColor = UIColor.black.withAlphaComponent(0.09)
        label.numberOfLines = 1
        addSubview(label)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !character.isEmpty else {
            label.text = nil
            return
        }
        let baselineY = bounds.height * GlyphRenderer.captureBaselineFraction
        let font = UIFont.systemFont(ofSize: Self.fontSize(for: character), weight: .light)
        label.font = font
        label.text = character
        // Anchor: the font's baseline sits exactly on the guide baseline.
        let lineHeight = font.ascender - font.descender
        label.frame = CGRect(x: 0, y: baselineY - font.ascender,
                             width: bounds.width, height: lineHeight)
    }

    /// Picks a font size whose cap height (uppercase, digits) or x-height
    /// (lowercase, everything else) matches the guide lines.
    static func fontSize(for character: String) -> CGFloat {
        let probe = UIFont.systemFont(ofSize: 100)
        let usesCapHeight: Bool
        if character.count == 1, let value = character.unicodeScalars.first?.value {
            usesCapHeight = (65...90).contains(value)      // A–Z
                || (192...221).contains(value)             // Ä Ö Ü etc.
                || (48...57).contains(value)               // 0–9
        } else {
            usesCapHeight = false
        }
        let target: CGFloat = usesCapHeight ? 100 : GlyphRenderer.captureXHeight
        let ratio = usesCapHeight ? probe.capHeight : probe.xHeight
        return target * (probe.pointSize / max(1, ratio))
    }
}
