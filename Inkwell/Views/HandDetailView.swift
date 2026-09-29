import SwiftUI

/// Progress grid for one handwriting set: grouped character cells, capture
/// flow entry, and hand settings.
struct HandDetailView: View {
    let handID: UUID

    @Environment(HandStore.self) private var hands
    @Environment(\.dismiss) private var dismiss
    @State private var captureIndex: Int?
    @State private var captureStartCharacter: String?
    @State private var showRename = false
    @State private var renameText = ""
    @State private var confirmingDelete = false

    private var hand: HandwritingSet? { hands.hand(id: handID) }

    var body: some View {
        Group {
            if let hand {
                content(hand)
            } else {
                ContentUnavailableView("Hand Deleted", systemImage: "trash")
            }
        }
    }

    private func content(_ hand: HandwritingSet) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if hand.geometryVersion == 0 && hand.doneCount > 0 {
                    migrationBanner(hand)
                }
                progressHeader(hand)
                ForEach(CharsetGroup.allCases) { group in
                    groupSection(group, hand: hand)
                }
                settingsSection(hand)
            }
            .padding(20)
        }
        .navigationTitle(hand.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    captureStartCharacter = nil
                    captureIndex = firstOpenIndex(hand: hand)
                } label: {
                    Label("Capture Characters", systemImage: "pencil.and.outline")
                }
            }
        }
        .sheet(item: Binding(
            get: { captureIndex.map { CaptureSession(index: $0) } },
            set: { captureIndex = $0?.index }
        )) { session in
            GlyphCaptureView(
                handID: handID,
                characters: CharsetGroup.allCharacters,
                index: Binding(
                    get: { captureIndex },
                    set: { captureIndex = $0 }
                ),
                onFinished: {}
            )
        }
        .alert("Rename", isPresented: $showRename) {
            TextField("Name", text: $renameText)
            Button("Rename") { hands.renameHand(handID, to: renameText) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete this handwriting and all captured characters?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                hands.deleteHand(handID)
                dismiss()
            }
        }
    }

    /// Old captures predate the baseline-anchoring fix and sit on the wrong
    /// baseline — offer a one-tap reset so the hand can be recaptured.
    private func migrationBanner(_ hand: HandwritingSet) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Capture geometry was fixed in this version — existing characters sit on the wrong baseline and must be recaptured.",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.orange)
            Button {
                hands.resetGlyphs(handID)
            } label: {
                Label("Reset & Recapture (\(hand.doneCount) characters)", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func progressHeader(_ hand: HandwritingSet) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(hand.doneCount) of \(hand.totalCount) characters")
                    .font(.headline)
                Spacer()
                Button {
                    renameText = hand.name
                    showRename = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                .buttonStyle(.borderless)
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.borderless)
            }
            ProgressView(value: Double(hand.doneCount), total: Double(max(1, hand.totalCount)))
                .tint(.accentColor)
            Text("Tap any character to draw or redraw it. Skip what you don't need — undrawn characters are simply left out of rendered text.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func groupSection(_ group: CharsetGroup, hand: HandwritingSet) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("\(group.title) · \(group.characters.filter { hand.isDone($0) }.count)/\(group.characters.count)")
                    .font(.subheadline.weight(.semibold))
            } icon: {
                Image(systemName: group.systemImage)
                    .foregroundStyle(.tint)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64, maximum: 84), spacing: 10)], spacing: 10) {
                ForEach(group.characters, id: \.self) { character in
                    GlyphCell(
                        character: character,
                        handID: handID,
                        isDone: hand.isDone(character),
                        isSkipped: hand.isSkipped(character),
                        variantCount: hand.variantCount(character)
                    ) {
                        captureIndex = CharsetGroup.allCharacters.firstIndex(of: character)
                    }
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func settingsSection(_ hand: HandwritingSet) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Writing Style").font(.subheadline.weight(.semibold))
            HStack {
                Text("Space width")
                    .font(.callout)
                Slider(
                    value: Binding(
                        get: { hand.spaceWidth },
                        set: { hands.setSpaceWidth(handID, fraction: $0) }
                    ),
                    in: 0.15...0.7
                )
                Text("\(Int(hand.spaceWidth * 100))%")
                    .font(.callout.monospacedDigit())
                    .frame(width: 46)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func firstOpenIndex(hand: HandwritingSet) -> Int? {
        CharsetGroup.allCharacters.firstIndex { !hand.isDone($0) }
    }
}

/// Identifiable wrapper so the capture sheet can be driven by an Int? index.
private struct CaptureSession: Identifiable {
    let index: Int
    var id: Int { index }
}

private struct GlyphCell: View {
    let character: String
    let handID: UUID
    let isDone: Bool
    let isSkipped: Bool
    let variantCount: Int
    let onTap: () -> Void

    @Environment(HandStore.self) private var hands
    @State private var thumbnail: UIImage?

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isDone ? AnyShapeStyle(PaperTheme.uiPaper.color) : AnyShapeStyle(Color.primary.opacity(0.05)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isDone ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.1),
                                          lineWidth: isDone ? 1.5 : 1)
                    )
                if isDone, let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .padding(6)
                } else if isSkipped {
                    Text(character)
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                        .overlay(
                            Rectangle().fill(.tertiary).frame(height: 1.5).rotationEffect(.degrees(-18))
                        )
                } else {
                    Text(character)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.tint)
                }
            }
            .aspectRatio(0.85, contentMode: .fit)
            .overlay(alignment: .topTrailing) {
                if isDone {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .padding(4)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if isDone && variantCount > 1 {
                    Text("×\(variantCount)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.accentColor, in: Capsule())
                        .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
        .task(id: "\(character)-\(isDone)") {
            thumbnail = isDone
                ? await hands.glyphThumbnail(handID: handID, character: character, side: 72)
                : nil
        }
    }
}
