import SwiftUI

/// GoodNotes-style notebook cover: gradient card with spine, title, page count.
struct NotebookCover: View {
    let notebook: Notebook

    private var theme: CoverTheme { CoverPalette.theme(notebook.coverColorIndex) }

    var body: some View {
        ZStack(alignment: .leading) {
            LinearGradient(colors: [theme.light, theme.dark],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(spacing: 0) {
                Rectangle().fill(.black.opacity(0.15)).frame(width: 16)
                Rectangle().fill(.white.opacity(0.14)).frame(width: 3)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 5) {
                Spacer()
                Text(notebook.name)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
                Text("\(notebook.pages.count) page\(notebook.pages.count == 1 ? "" : "s")")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
            }
            .padding(16)
            .padding(.leading, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .aspectRatio(0.72, contentMode: .fit)
        .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
    }
}

/// Small cover thumbnail for sidebar rows.
struct MiniCover: View {
    let notebook: Notebook

    private var theme: CoverTheme { CoverPalette.theme(notebook.coverColorIndex) }

    var body: some View {
        ZStack(alignment: .leading) {
            LinearGradient(colors: [theme.light, theme.dark],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Rectangle().fill(.black.opacity(0.15)).frame(width: 8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .frame(width: 48, height: 34)
        .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
    }
}
