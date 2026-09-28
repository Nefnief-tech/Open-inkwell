import SwiftUI
import PhotosUI
import PencilKit

/// Type text, pick a hand + background, match the line spacing — the
/// handwriting scales automatically. Export as PNG or PDF.
struct DocumentEditorView: View {
    let docID: UUID

    @Environment(DocumentStore.self) private var documents
    @Environment(HandStore.self) private var hands
    @Environment(\.displayScale) private var displayScale

    @State private var glyphs: [String: PKDrawing] = [:]
    @State private var background: UIImage?
    @State private var preview: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var showShare = false
    @State private var shareURL: URL?
    @State private var showGuides = false
    @State private var isExporting = false
    @State private var showRename = false
    @State private var renameText = ""

    private var doc: HandDocument? { documents.document(id: docID) }

    /// Re-renders the preview whenever any of these change.
    private var previewKey: String {
        guard let doc else { return "" }
        return [
            doc.text, doc.handID.uuidString, doc.template.rawValue,
            String(doc.lineSpacing), String(doc.letterSpacing),
            String(doc.sizeMultiplier), String(doc.inkColorIndex),
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

    private func editor(_ doc: HandDocument) -> some View {
        VStack(spacing: 0) {
            previewPane(doc)
            controls(doc)
        }
        .navigationTitle(doc.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                exportMenu(doc)
            }
        }
        .task(id: doc.handID) {
            glyphs = await hands.allGlyphs(handID: doc.handID)
            background = doc.usesBackgroundImage
                ? await documents.loadBackground(docID: docID) : nil
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

    // MARK: - Preview

    private func previewPane(_ doc: HandDocument) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(glyphs.isEmpty ? "Capture characters in “\(handName(doc))” first" : "Preview")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("Guides", isOn: $showGuides)
                    .toggleStyle(.button)
                    .font(.caption)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            ZStack {
                if let preview {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFit()
                        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(PaperTheme.uiPaper.color)
                        .aspectRatio(GlyphRenderer.blankPageSize.width / GlyphRenderer.blankPageSize.height,
                                     contentMode: .fit)
                        .overlay(ProgressView())
                }
                if showGuides {
                    BaselineGuidesOverlay(lineSpacing: doc.lineSpacing,
                                          firstBaseline: doc.lineSpacing)
                        .allowsHitTesting(false)
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 340)
        .background(.bar)
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
                Text("Import a photo of your paper, then match the line spacing below — the handwriting scales to fit automatically.")
            }

            Section("Fit & Style") {
                sliderRow("Line spacing", value: Binding(
                    get: { doc.lineSpacing },
                    set: { var d = doc; d.lineSpacing = $0; documents.update(d) }
                ), in: 30...200, format: "%.0f pt")
                sliderRow("Letter spacing", value: Binding(
                    get: { doc.letterSpacing },
                    set: { var d = doc; d.letterSpacing = $0; documents.update(d) }
                ), in: 0...14, format: "%.1f")
                sliderRow("Text size", value: Binding(
                    get: { doc.sizeMultiplier },
                    set: { var d = doc; d.sizeMultiplier = $0; documents.update(d) }
                ), in: 0.6...1.8, format: "%.2f×")

                HStack {
                    Text("Ink")
                    Spacer()
                    HStack(spacing: 8) {
                        ForEach(InkPalette.colors.indices, id: \.self) { index in
                            Button {
                                var d = doc; d.inkColorIndex = index; documents.update(d)
                            } label: {
                                Circle()
                                    .fill(InkPalette.colors[index])
                                    .frame(width: 22, height: 22)
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

    // MARK: - Export

    private func exportMenu(_ doc: HandDocument) -> some View {
        Menu {
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
                Label("Export", systemImage: "square.and.arrow.up")
            }
        }
        .disabled(glyphs.isEmpty)
    }

    private func export(_ doc: HandDocument, asPDF: Bool) {
        isExporting = true
        let scale: CGFloat = 3
        let size = pageSize(doc)
        let ink = InkPalette.uiColors[doc.inkColorIndex]
        let composed = GlyphRenderer.compose(text: doc.text, glyphs: glyphs, settings: composeSettings(doc, ink: ink))
        let bgImage = doc.usesBackgroundImage ? background : nil
        let name = doc.name.replacingOccurrences(of: "/", with: "-")
        Task.detached(priority: .userInitiated) {
            var url: URL?
            if asPDF {
                let data = GlyphRenderer.renderPDF(size: size, background: bgImage,
                                                   template: doc.template, composed: composed)
                url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(name).pdf")
                try? data.write(to: url!)
            } else {
                let image = GlyphRenderer.renderPage(size: size, scale: scale,
                                                     background: bgImage, template: doc.template,
                                                     composed: composed)
                url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(name).png")
                try? image.pngData()?.write(to: url!)
            }
            await MainActor.run {
                isExporting = false
                if let url {
                    shareURL = url
                    showShare = true
                }
            }
        }
    }

    // MARK: - Helpers

    private func handName(_ doc: HandDocument) -> String {
        hands.hand(id: doc.handID)?.name ?? "hand"
    }

    private func pageSize(_ doc: HandDocument) -> CGSize {
        if doc.usesBackgroundImage, let background {
            return background.size
        }
        return GlyphRenderer.blankPageSize
    }

    private func composeSettings(_ doc: HandDocument, ink: UIColor?) -> GlyphRenderer.ComposeSettings {
        GlyphRenderer.ComposeSettings(
            lineSpacing: CGFloat(doc.lineSpacing),
            letterSpacing: CGFloat(doc.letterSpacing),
            sizeMultiplier: CGFloat(doc.sizeMultiplier),
            spaceWidthFraction: hands.hand(id: doc.handID)?.spaceWidth ?? 0.35,
            pageWidth: pageSize(doc).width,
            firstBaseline: CGFloat(doc.lineSpacing),
            inkColor: ink
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
            }
            if let doc = documents.document(id: docID) {
                glyphs = await hands.allGlyphs(handID: doc.handID)
            }
            photoItem = nil
        }
    }
}

/// Horizontal guide lines matching the composed baselines.
struct BaselineGuidesOverlay: View {
    var lineSpacing: CGFloat
    var firstBaseline: CGFloat

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                var y = firstBaseline
                while y < size.height {
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(path, with: .color(.red.opacity(0.35)),
                                   style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
                    y += lineSpacing
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
