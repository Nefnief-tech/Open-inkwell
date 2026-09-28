import SwiftUI

/// Grid of handwriting sets, GoodNotes-cover style cards.
struct HandsListView: View {
    @Environment(HandStore.self) private var hands
    @State private var path: [UUID] = []
    @State private var showCreate = false
    @State private var newName = ""
    @State private var deleting: HandwritingSet?
    @State private var renaming: HandwritingSet?
    @State private var renameText = ""

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if hands.hands.isEmpty {
                    ContentUnavailableView {
                        Label("No Handwriting Yet", systemImage: "hand.draw")
                    } description: {
                        Text("Create a handwriting set, then draw the characters you need — guided, character by character. Skip anything you don't use.")
                    } actions: {
                        Button("Create Handwriting") { showCreate = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 180, maximum: 300), spacing: 20)],
                            spacing: 26
                        ) {
                            ForEach(hands.hands) { hand in
                                handCard(hand)
                            }
                        }
                        .padding(24)
                    }
                }
            }
            .navigationTitle("My Hands")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showCreate = true } label: {
                        Label("New Handwriting", systemImage: "plus")
                    }
                }
            }
            .alert("New Handwriting", isPresented: $showCreate) {
                TextField("Name (e.g. “My Print”)", text: $newName)
                Button("Create") {
                    let hand = hands.createHand(named: newName)
                    newName = ""
                    path.append(hand.id)
                }
                Button("Cancel", role: .cancel) { newName = "" }
            }
            .alert(
                "Rename Handwriting",
                isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
            ) {
                TextField("Name", text: $renameText)
                Button("Rename") {
                    if let hand = renaming { hands.renameHand(hand.id, to: renameText) }
                    renaming = nil
                }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
            .confirmationDialog(
                "Delete “\(deleting?.name ?? "")” and all captured characters?",
                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let hand = deleting { hands.deleteHand(hand.id) }
                    deleting = nil
                }
                Button("Cancel", role: .cancel) { deleting = nil }
            }
            .navigationDestination(for: UUID.self) { handID in
                HandDetailView(handID: handID)
            }
        }
    }

    private func handCard(_ hand: HandwritingSet) -> some View {
        Button { path.append(hand.id) } label: {
            HandCard(hand: hand)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                renameText = hand.name
                renaming = hand
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                deleting = hand
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

private struct HandCard: View {
    let hand: HandwritingSet

    private var theme: CoverTheme { CoverPalette.theme(hand.id.hashValue) }
    private var progress: Double {
        hand.totalCount == 0 ? 0 : Double(hand.doneCount) / Double(hand.totalCount)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [theme.light, theme.dark],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 6) {
                Spacer()
                Text(hand.name)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text("\(hand.doneCount)/\(hand.totalCount) characters")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                ProgressView(value: progress)
                    .tint(.white)
            }
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .aspectRatio(0.85, contentMode: .fit)
        .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
    }
}
