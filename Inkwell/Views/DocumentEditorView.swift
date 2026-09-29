import SwiftUI
import PhotosUI
import PencilKit

/// Type text, pick a hand + background, calibrate the line grid by dragging
/// guides right on the paper — the handwriting scales automatically.
/// Large preview with the controls in a side panel on iPad.
struct DocumentEditorView: View {
    let docID: UUID

    @Environment(DocumentStore.self) private var documents
    @Environment(HandStore.self) private var hands
    @Environment(\.displayScale) private var displayScale
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var glyphs: [String: [PKDrawing]] = [:]
    @State private var background: UIImage?
    @State private var preview: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var showShare = false
    @State private var shareURL: URL?
    @State private var showGuides = false
    @State private var calibrating = false
    @State private var isExporting = false
    @State private var showRename = false
    @State private var renameText = ""

    // Drag calibration state: which line, and its value when the drag began.
    @State private var dragKind: CalibLineKind?
    @State private var dragStartValue: Double = 0

    private enum CalibLineKind { case firstBaseline, spacing, leftMargin }

    private var doc: HandDocument? { documents.document(id: docID) }

    /// Re-renders the preview whenever any of these change.
    private var previewKey: String {
        guard let doc else { return "" }
        return [
            doc.text, doc.handID.uuidString, doc.template.rawValue,
            String(doc.lineSpacing), String(doc.letterSpacing),
            String(doc.sizeMultiplier), String(doc.inkColorIndex),
            String(doc.leftMargin), String(doc.firstBaseline),
            String(doc.variationSeed),
            doc.snapToRuling ? "snap" : "free",
            (doc.rulingBaselines ?? []).map { String(Int($0)) }.joined(separator: ","),
            doc.usesBackgroundImage ? "bg" : "paper",
        ].joined(separator: "|")
    }

    var body: some View {
        Group {
            if let doc {
                editor(doc)
            } else {
                ContentUnavailableView("Document Deleted", systemImage: "trash")
            }
        }
    }

    // MARK: - Layout

    private func editor(_ doc: HandDocument) -> some View {
        Group {
            if sizeClass == .regular {
                HStack(spacing: 0) {
                    previewPane(doc)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    controls(doc)
                        .frame(width: 370)
                }
            } else {
                VStack(spacing: 0) {
                    previewPane(doc)
                        .frame(height: 320)
                    controls(doc)
                }
            }
        }
        .navigationTitle(doc.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                editorMenu(doc)
            }
        }
        .task(id: doc.handID) {
            glyphs = await hands.allGlyphs(handID: doc.handID)
            background = doc.usesBackgroundImage
                ? await documents.loadBackground(docID: docID) : nil
            if let bg = background, doc.rulingBaselines == nil {
                await detectAndStoreRuling(bg)
            }
        }
        .task(id: previewKey) {
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            renderPreview(doc)
        }
        .onChange(of: photoItem) { _, item in
            importPhoto(item)
        }
        .sheet(isPresented: $showShare) {
            if let shareURL {
                ShareSheet(items: [shareURL])
            }
        }
        .alert("Rename", isPresented: $showRename) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                documents.renameDocument(docID, to: renameText)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func editorMenu(_ doc: HandDocument) -> some View {
        Menu {
            Button {
                renameText = doc.name
                showRename = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button {
                documents.duplicateDocument(docID)
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            Divider()
            Button {
                export(doc, asPDF: false)
            } label: {
                Label("Export as PNG", systemImage: "photo")
            }
            Button {
                export(doc, asPDF: true)
            } label: {
                Label("Export as PDF", systemImage: "doc.richtext")
            }
        } label: {
            if isExporting {
                ProgressView()
            } else {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
        .disabled(glyphs.isEmpty)
    }

    // MARK: - Preview

    private func previewPane(_ doc: HandDocument) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                let oldGeometry = hands.hand(id: doc.handID)?.geometryVersion == 0
                Text(glyphs.isEmpty
                     ? "Capture characters in “\(handName(doc))” first"
                     : oldGeometry
                       ? "⚠︎ Old capture geometry — recapture this hand in My Hands or lines won't match"
                       : "Preview")
                    .font(.caption)
                    .foregroundStyle(oldGeometry ? .orange : .secondary)
                Spacer()
                Toggle("Align", isOn: $calibrating.animation())
                    .toggleStyle(.button)
                    .font(.caption)
                    .disabled(preview == nil)
                Toggle("Guides", isOn: $showGuides)
                    .toggleStyle(.button)
                    .font(.caption)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            GeometryReader { geo in
                let page = pageSize(doc)
                let rect = fittedRect(geo.size, page: page)
                let scale = rect.height / max(1, page.height)
                ZStack {
                    if let preview {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFit()
                            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                    }
                    if showGuides {
                        BaselineGuidesOverlay(baselineYs: guideYs(doc, scale: scale))
                            .allowsHitTesting(false)
                    }
                    if calibrating {
                        calibrationLines(doc, rect: rect, scale: scale)
                    }
                }
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .coordinateSpace(name: "calibSpace")
            }
            .padding(16)
        }
    }

    /// Two draggable horizontal lines (first line + second line → spacing)
    /// and a draggable vertical line (line start / left margin). While
    /// snapping to detected ruling, the horizontal drags are hidden (the
    /// paper's own lines define the grid); the line start stays draggable.
    @ViewBuilder
    private func calibrationLines(_ doc: HandDocument, rect: CGRect, scale: CGFloat) -> some View {
        if !isSnapping(doc) {
            calibHorizontalLine(
                kind: .firstBaseline,
                y: CGFloat(doc.firstBaseline) * scale,
                label: "1st line", color: .red,
                containerHeight: rect.height, scale: scale,
                currentValue: doc.firstBaseline
            ) { start, delta in
                guard var d = documents.document(id: docID) else { return }
                d.firstBaseline = (start + delta).clamped(20...(pageSize(d).height - 20))
                documents.update(d)
            }
            calibHorizontalLine(
                kind: .spacing,
                y: CGFloat(doc.firstBaseline + doc.lineSpacing) * scale,
                label: "spacing", color: .orange,
                containerHeight: rect.height, scale: scale,
                currentValue: doc.lineSpacing
            ) { start, delta in
                guard var d = documents.document(id: docID) else { return }
                d.lineSpacing = (start + delta).clamped(20...300)
                documents.update(d)
            }
        }
        calibVerticalLine(
            x: CGFloat(doc.leftMargin) * scale,
            label: "start", color: .blue,
            containerWidth: rect.width, scale: scale,
            currentValue: doc.leftMargin
        ) { start, delta in
            guard var d = documents.document(id: docID) else { return }
            d.leftMargin = (start + delta).clamped(0...240)
            documents.update(d)
        }
    }

    private func hCalibGesture(kind: CalibLineKind, currentValue: Double, scale: CGFloat,
                               apply: @escaping (Double, Double) -> Void) -> some Gesture {
        DragGesture(coordinateSpace: .named("calibSpace"))
            .onChanged { g in
                if dragKind != kind {
                    dragKind = kind
                    dragStartValue = currentValue
                }
                apply(dragStartValue, Double(g.translation.height / scale))
            }
            .onEnded { _ in dragKind = nil }
    }

    private func vCalibGesture(kind: CalibLineKind, currentValue: Double, scale: CGFloat,
                               apply: @escaping (Double, Double) -> Void) -> some Gesture {
        DragGesture(coordinateSpace: .named("calibSpace"))
            .onChanged { g in
                if dragKind != kind {
                    dragKind = kind
                    dragStartValue = currentValue
                }
                apply(dragStartValue, Double(g.translation.width / scale))
            }
            .onEnded { _ in dragKind = nil }
    }

    private func calibHorizontalLine(kind: CalibLineKind, y: CGFloat, label: String,
                                     color: Color, containerHeight: CGFloat, scale: CGFloat,
                                     currentValue: Double,
                                     apply: @escaping (Double, Double) -> Void) -> some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(color.opacity(0.8))
                .frame(height: 1.5)
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal")
                Text(label).font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color, in: Capsule())
            .padding(.leading, 8)
        }
        .frame(maxWidth: .infinity, minHeight: 34)
        .contentShape(Rectangle())
        .offset(y: y - containerHeight / 2)
        .gesture(hCalibGesture(kind: kind, currentValue: currentValue,
                               scale: scale, apply: apply))
    }

    private func calibVerticalLine(x: CGFloat, label: String, color: Color,
                                   containerWidth: CGFloat, scale: CGFloat,
                                   currentValue: Double,
                                   apply: @escaping (Double, Double) -> Void) -> some View {
        ZStack {
            Rectangle()
                .fill(color.opacity(0.8))
                .frame(width: 1.5)
            VStack(spacing: 4) {
                Image(systemName: "arrow.left.and.right")
                Text(label).font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(color, in: Capsule())
        }
        .frame(minWidth: 34, maxHeight: .infinity)
        .contentShape(Rectangle())
        .offset(x: x - containerWidth / 2)
        .gesture(vCalibGesture(kind: .leftMargin, currentValue: currentValue,
                               scale: scale, apply: apply))
    }

    // MARK: - Controls

    private func controls(_ doc: HandDocument) -> some View {
        Form {
            Section("Text") {
                TextEditor(text: Binding(
                    get: { doc.text },
                    set: { var d = doc; d.text = $0; documents.update(d) }
                ))
                .frame(minHeight: 90)
            }

            Section("Handwriting") {
                Picker("Hand", selection: Binding(
                    get: { doc.handID },
                    set: { var d = doc; d.handID = $0; documents.update(d) }
                )) {
                    ForEach(hands.hands) { hand in
                        Text(hand.name).tag(hand.id)
                    }
                }
            }

            Section {
                if doc.usesBackgroundImage {
                    if let background {
                        Image(uiImage: background)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 90)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    Button(role: .destructive) {
                        documents.removeBackground(docID: docID)
                        background = nil
                    } label: {
                        Label("Remove Photo", systemImage: "trash")
                    }
                } else {
                    Picker("Blank Paper", selection: Binding(
                        get: { doc.template },
                        set: { var d = doc; d.template = $0; documents.update(d) }
                    )) {
                        ForEach(PaperTemplate.allCases) { template in
                            Label(template.displayName, systemImage: template.systemImage)
                                .tag(template)
                        }
                    }
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Import Background Photo…", systemImage: "photo.badge.plus")
                }
            } header: {
                Text("Background")
            } footer: {
                Text("Import a photo of your paper, then drag the guides in Align mode — spacing and line start are calculated for you. Fine-tune below; the handwriting scales to fit automatically.")
            }

            Section {
                Toggle("Snap to paper lines", isOn: Binding(
                    get: { doc.snapToRuling && doc.rulingBaselines != nil },
                    set: { var d = doc; d.snapToRuling = $0; documents.update(d) }
                ))
                .disabled(!doc.usesBackgroundImage || doc.rulingBaselines == nil)

                if doc.usesBackgroundImage {
                    if let ruling = doc.rulingBaselines {
                        LabeledContent("Detected ruling lines", value: "\(ruling.count)")
                    } else {
                        Label("No ruling detected — using uniform spacing", systemImage: "questionmark.circle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        if let bg = background {
                            Task { await detectAndStoreRuling(bg) }
                        }
                    } label: {
                        Label("Re-detect Lines", systemImage: "viewfinder")
                    }
                }

                sliderRow("Line spacing", value: Binding(
                    get: { doc.lineSpacing },
                    set: { var d = doc; d.lineSpacing = $0; documents.update(d) }
                ), in: 20...300, format: "%.0f pt")
                .disabled(isSnapping(doc))
                sliderRow("First line", value: Binding(
                    get: { doc.firstBaseline },
                    set: { var d = doc; d.firstBaseline = $0; documents.update(d) }
                ), in: 20...400, format: "%.0f pt")
                .disabled(isSnapping(doc))
                sliderRow("Line start", value: Binding(
                    get: { doc.leftMargin },
                    set: { var d = doc; d.leftMargin = $0; documents.update(d) }
                ), in: 0...240, format: "%.0f pt")
                sliderRow("Letter spacing", value: Binding(
                    get: { doc.letterSpacing },
                    set: { var d = doc; d.letterSpacing = $0; documents.update(d) }
                ), in: 0...14, format: "%.1f")
                sliderRow("Text size", value: Binding(
                    get: { doc.sizeMultiplier },
                    set: { var d = doc; d.sizeMultiplier = $0; documents.update(d) }
                ), in: 0.4...2.5, format: "%.2f×")

                // Exact now: glyph scale no longer depends on line spacing.
                let xHeight = Int((GlyphRenderer.xHeightSpan
                                   * (GlyphRenderer.naturalLineSpacing / GlyphRenderer.naturalLineAdvance)
                                   * doc.sizeMultiplier).rounded())
                LabeledContent("Resulting x-height", value: "≈ \(xHeight) pt")

                HStack {
                    Button {
                        var d = doc
                        d.sizeMultiplier = min(2.5, max(0.4,
                            d.sizeMultiplier * (d.lineSpacing / GlyphRenderer.naturalLineSpacing)))
                        documents.update(d)
                    } label: {
                        Label("Fit to Ruling", systemImage: "arrow.down.forward.and.arrow.up.backward")
                    }
                    .buttonStyle(.bordered)
                    Button {
                        var d = doc
                        d.variationSeed = Int.random(in: 0...Int(Int32.max))
                        documents.update(d)
                    } label: {
                        Label("Shuffle Variations", systemImage: "shuffle")
                    }
                    .buttonStyle(.bordered)
                }
            } header: {
                Text("Fit & Style")
            } footer: {
                Text("Text size and line spacing are independent: resizing text never moves the lines. With a photo background, “Snap to paper lines” places every line of text on its own detected ruling line — perfect match over any number of lines, no calibration needed. “Fit to Ruling” snaps the text size proportionally to the current spacing.")
            }

            Section("Ink") {
                HStack(spacing: 10) {
                    ForEach(InkPalette.colors.indices, id: \.self) { index in
                        Button {
                            var d = doc; d.inkColorIndex = index; documents.update(d)
                        } label: {
                            Circle()
                                .fill(InkPalette.colors[index])
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Circle().strokeBorder(
                                        doc.inkColorIndex == index ? Color.primary : .clear,
                                        lineWidth: 2
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func sliderRow(_ label: String, value: Binding<Double>, in range: ClosedRange<Double>,
                           format: String) -> some View {
        HStack {
            Text(label)
                .font(.callout)
            Slider(value: value, in: range)
            Text(String(format: format, value.wrappedValue))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
        }
    }

    // MARK: - Helpers

    private func handName(_ doc: HandDocument) -> String {
        hands.hand(id: doc.handID)?.name ?? "hand"
    }

    private func isSnapping(_ doc: HandDocument) -> Bool {
        doc.snapToRuling && doc.usesBackgroundImage && doc.rulingBaselines != nil
    }

    /// Guide line Ys in preview screen points: detected ruling when snapping,
    /// otherwise the uniform grid.
    private func guideYs(_ doc: HandDocument, scale: CGFloat) -> [CGFloat] {
        if isSnapping(doc), let ruling = doc.rulingBaselines {
            return ruling.map { CGFloat($0) * scale }
        }
        let pageHeight = pageSize(doc).height
        var ys: [CGFloat] = []
        var y = CGFloat(doc.firstBaseline)
        while y <= pageHeight + 1 {
            ys.append(y * scale)
            y += CGFloat(doc.lineSpacing)
        }
        return ys
    }

    private func pageSize(_ doc: HandDocument) -> CGSize {
        if doc.usesBackgroundImage, let background {
            return background.size
        }
        return GlyphRenderer.blankPageSize
    }

    private func fittedRect(_ container: CGSize, page: CGSize) -> CGRect {
        guard page.width > 0, page.height > 0, container.width > 0, container.height > 0 else {
            return .zero
        }
        let s = min(container.width / page.width, container.height / page.height)
        let w = page.width * s
        let h = page.height * s
        return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2,
                      width: w, height: h)
    }

    private func composeSettings(_ doc: HandDocument, ink: UIColor?) -> GlyphRenderer.ComposeSettings {
        let snapping = doc.snapToRuling && doc.usesBackgroundImage
        var ruling: [CGFloat]? = nil
        if snapping, let values = doc.rulingBaselines {
            ruling = values.map { CGFloat($0) }
        }
        return GlyphRenderer.ComposeSettings(
            lineSpacing: CGFloat(doc.lineSpacing),
            letterSpacing: CGFloat(doc.letterSpacing),
            sizeMultiplier: CGFloat(doc.sizeMultiplier),
            spaceWidthFraction: hands.hand(id: doc.handID)?.spaceWidth ?? 0.35,
            pageWidth: pageSize(doc).width,
            leftMargin: CGFloat(doc.leftMargin),
            firstBaseline: CGFloat(doc.firstBaseline),
            inkColor: ink,
            variationSeed: UInt64(bitPattern: Int64(doc.variationSeed)),
            lineBaselines: ruling
        )
    }

    private func renderPreview(_ doc: HandDocument) {
        let ink = InkPalette.uiColors[doc.inkColorIndex]
        let composed = GlyphRenderer.compose(text: doc.text, glyphs: glyphs,
                                             settings: composeSettings(doc, ink: ink))
        let image = GlyphRenderer.renderPage(size: pageSize(doc), scale: 1,
                                             background: doc.usesBackgroundImage ? background : nil,
                                             template: doc.template, composed: composed)
        preview = image
        documents.saveThumbnail(docID: docID, image: image)
    }

    private func importPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                await documents.saveBackground(docID: docID, imageData: data)
                background = await documents.loadBackground(docID: docID)
                if let bg = background {
                    await detectAndStoreRuling(bg)
                }
            }
            if let doc = documents.document(id: docID) {
                glyphs = await hands.allGlyphs(handID: doc.handID)
            }
            photoItem = nil
        }
    }

    /// Finds the paper's ruling lines and enables snapping when found.
    private func detectAndStoreRuling(_ bg: UIImage) async {
        let lines = await Task.detached(priority: .utility) {
            RulingDetector.detectLines(in: bg)
        }.value
        if var d = documents.document(id: docID) {
            d.rulingBaselines = lines.map { $0.map { Double($0) } }
            if lines != nil { d.snapToRuling = true }
            documents.update(d)
        }
    }

    private func export(_ doc: HandDocument, asPDF: Bool) {
        isExporting = true
        let scale: CGFloat = 3
        let size = pageSize(doc)
        let ink = InkPalette.uiColors[doc.inkColorIndex]
        let composed = GlyphRenderer.compose(text: doc.text, glyphs: glyphs, settings: composeSettings(doc, ink: ink))
        let bgImage = doc.usesBackgroundImage ? background : nil
        let name = doc.name.replacingOccurrences(of: "/", with: "-")
        Task {
            let url: URL? = await Task.detached(priority: .userInitiated) { () -> URL? in
                let url: URL
                if asPDF {
                    let data = GlyphRenderer.renderPDF(size: size, background: bgImage,
                                                       template: doc.template, composed: composed)
                    url = FileManager.default.temporaryDirectory
                        .appendingPathComponent("\(name).pdf")
                    try? data.write(to: url, options: .atomic)
                } else {
                    let image = GlyphRenderer.renderPage(size: size, scale: scale,
                                                         background: bgImage, template: doc.template,
                                                         composed: composed)
                    url = FileManager.default.temporaryDirectory
                        .appendingPathComponent("\(name).png")
                    try? image.pngData()?.write(to: url, options: .atomic)
                }
                return url
            }.value
            isExporting = false
            if let url {
                shareURL = url
                showShare = true
            }
        }
    }
}

/// Horizontal baseline guide lines matching the composed text layout,
/// passed already scaled to the preview's display size.
struct BaselineGuidesOverlay: View {
    var baselineYs: [CGFloat]

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                for y in baselineYs where y >= -1 && y <= size.height + 1 {
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(path, with: .color(.red.opacity(0.35)),
                                   style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
                }
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

extension Double {
    func clamped(_ range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
