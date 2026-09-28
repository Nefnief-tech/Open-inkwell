import SwiftUI
import PencilKit

// MARK: - Tool configuration

enum ToolKind: String, CaseIterable, Identifiable {
    case pen, pencil, marker, eraser

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .pen: return "pencil.tip"
        case .pencil: return "pencil"
        case .marker: return "highlighter"
        case .eraser: return "eraser.fill"
        }
    }

    var displayName: String {
        switch self {
        case .pen: return "Pen"
        case .pencil: return "Pencil"
        case .marker: return "Marker"
        case .eraser: return "Eraser"
        }
    }
}

struct ToolConfig: Hashable {
    var kind: ToolKind = .pen
    var colorIndex: Int = 0
    var widthIndex: Int = 1

    var pkTool: PKTool {
        let width = InkPalette.widths[max(0, min(widthIndex, InkPalette.widths.count - 1))]
        let color = InkPalette.uiColors[max(0, min(colorIndex, InkPalette.uiColors.count - 1))]
        switch kind {
        case .pen: return PKInkingTool(.pen, color: color, width: width)
        case .pencil: return PKInkingTool(.pencil, color: color, width: width)
        case .marker: return PKInkingTool(.marker, color: color, width: width * 1.7)
        case .eraser: return PKEraserTool(.vector)
        }
    }
}

/// Bridges toolbar buttons to the live canvas (undo/redo via UndoManager).
@MainActor
final class CanvasController: ObservableObject {
    weak var canvas: PKCanvasView?

    func undo() { canvas?.undoManager?.undo() }
    func redo() { canvas?.undoManager?.redo() }
}

// MARK: - The floating tool block

/// Custom Pencil toolbar: tools, ink colors, stroke widths, undo/redo.
struct ToolBlock: View {
    @Binding var config: ToolConfig
    var controller: CanvasController
    var onHide: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            tools
            blockDivider
            colors
            blockDivider
            widths
            blockDivider
            historyButtons
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassCapsuleBackground()
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }

    private var tools: some View {
        HStack(spacing: 8) {
            ForEach(ToolKind.allCases) { kind in
                Button {
                    config.kind = kind
                } label: {
                    Image(systemName: kind.systemImage)
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 34, height: 34)
                        .background(
                            config.kind == kind ? Color.accentColor.opacity(0.18) : Color.clear,
                            in: Circle()
                        )
                        .foregroundStyle(config.kind == kind ? Color.accentColor : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(kind.displayName)
            }
        }
    }

    private var colors: some View {
        HStack(spacing: 7) {
            ForEach(InkPalette.colors.indices, id: \.self) { index in
                Button {
                    config.colorIndex = index
                    if config.kind == .eraser { config.kind = .pen }
                } label: {
                    Circle()
                        .fill(InkPalette.colors[index])
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle().strokeBorder(
                                config.colorIndex == index ? Color.primary.opacity(0.85) : Color.primary.opacity(0.12),
                                lineWidth: config.colorIndex == index ? 2 : 1
                            )
                        )
                }
                .buttonStyle(.plain)
                .opacity(config.kind == .eraser ? 0.35 : 1)
            }
        }
    }

    private var widths: some View {
        HStack(spacing: 8) {
            ForEach(InkPalette.widths.indices, id: \.self) { index in
                Button {
                    config.widthIndex = index
                    if config.kind == .eraser { config.kind = .pen }
                } label: {
                    Circle()
                        .fill(Color.primary)
                        .frame(width: [6, 9, 13][index], height: [6, 9, 13][index])
                        .opacity(config.widthIndex == index ? 1 : 0.35)
                        .frame(width: 26, height: 26)
                        .background(
                            config.widthIndex == index ? Color.primary.opacity(0.1) : Color.clear,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .opacity(config.kind == .eraser ? 0.35 : 1)
            }
        }
    }

    private var historyButtons: some View {
        HStack(spacing: 8) {
            Button {
                controller.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 15, weight: .medium))
            }
            Button {
                controller.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 15, weight: .medium))
            }
            Button {
                onHide()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .medium))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private var blockDivider: some View {
        Divider()
            .frame(height: 26)
    }
}

/// Liquid Glass on iPadOS 26+, regular material below.
struct GlassCapsuleBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(in: Capsule())
        } else {
            content
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.quaternary))
        }
    }
}

extension View {
    func glassCapsuleBackground() -> some View {
        modifier(GlassCapsuleBackground())
    }
}
