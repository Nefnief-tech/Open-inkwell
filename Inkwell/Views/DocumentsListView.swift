import SwiftUI

/// Grid of documents with rendered preview thumbnails.
struct DocumentsListView: View {
    @Environment(DocumentStore.self) private var documents
    @Environment(HandStore.self) private var hands

    @State private var path: [UUID] = []
    @State private var showCreate = false
    @State private var newName = ""
    @State private var selectedHandID: UUID?
    @State private var deleting: HandDocument?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if hands.hands.isEmpty {
                    ContentUnavailableView {
                        Label("Create a Handwriting First", systemImage: "hand.draw")
                    } description: {
                        Text("Documents render typed text in one of your handwriting sets. Open “My Hands” in the sidebar to capture your first handwriting.")
                    }
                } else if documents.documents.isEmpty {
                    ContentUnavailableView {
                        Label("No Documents", systemImage: "doc.on.doc")
                    } description: {
                        Text("Create a document, type your text, and it appears in your handwriting.")
                    } actions: {
                        Button("Create Document") { showCreate = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 180, maximum: 300), spacing: 20)],
                            spacing: 26
                        ) {
                            ForEach(documents.documents) { doc in
                                docCard(doc)
                            }
                        }
                        .padding(24)
                    }
                }
            }
            .navigationTitle("Documents")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        selectedHandID = hands.hands.first?.id
                        showCreate = true
                    } label: {
                        Label("New Document", systemImage: "plus")
                    }
                    .disabled(hands.hands.isEmpty)
                }
            }
            .navigationDestination(for: UUID.self) { id in
                DocumentEditorView(docID: id)
            }
            .sheet(isPresented: $showCreate) {
                createSheet
            }
            .confirmationDialog(
                "Delete “\(deleting?.name ?? "")”?",
                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let doc = deleting { documents.deleteDocument(doc.id) }
                    deleting = nil
                }
                Button("Cancel", role: .cancel) { deleting = nil }
            }
        }
    }

    private var createSheet: some View {
        NavigationStack {
            Form {
                TextField("Name (e.g. “Homework pg. 4”)", text: $newName)
                Picker("Handwriting", selection: $selectedHandID) {
                    ForEach(hands.hands) { hand in
                        Text(hand.name).tag(Optional(hand.id))
                    }
                }
                if (hands.hand(id: selectedHandID)?.doneCount ?? 0) == 0 {
                    Label("This hand has no captured characters yet — capture some first.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .navigationTitle("New Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showCreate = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        if let handID = selectedHandID {
                            let doc = documents.createDocument(handID: handID,
                                                               name: newName.isEmpty ? "Untitled" : newName)
                            newName = ""
                            showCreate = false
                            path.append(doc.id)
                        }
                    }
                    .disabled(selectedHandID == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func docCard(_ doc: HandDocument) -> some View {
        Button {
            path.append(doc.id)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                DocumentThumbnail(doc: doc)
                Text(doc.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(hands.hand(id: doc.handID)?.name ?? "—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                documents.duplicateDocument(doc.id)
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            Button(role: .destructive) {
                deleting = doc
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

private struct DocumentThumbnail: View {
    let doc: HandDocument

    @Environment(DocumentStore.self) private var documents
    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(PaperTheme.uiPaper.color)
                .shadow(color: .black.opacity(0.14), radius: 8, y: 4)
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                Image(systemName: "textformat")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
            }
        }
        .aspectRatio(0.78, contentMode: .fit)
        .task(id: doc.id) {
            thumbnail = await documents.loadThumbnail(docID: doc.id)
        }
    }
}
