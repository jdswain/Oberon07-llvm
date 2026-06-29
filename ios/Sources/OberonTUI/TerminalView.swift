// TerminalView — SwiftUI cell-grid view backed by TerminalState.
//
// Scaffold-grade: renders each row as a single Text via an attributed
// string built from the cells. Good enough to see Oberon output on
// screen and exercise the runtime end-to-end. The web port runs span-
// per-cell so per-cell background colour can be styled; the SwiftUI
// equivalent (separate styled Text per cell, or a Canvas drawing) is
// the next iteration once oed itself drives the contents.
//
// Geometry: a monospace font + GeometryReader measures available
// space and reports rows/cols back to TerminalState. The view
// invokes `onReady` once after the first stable resize — the
// embedding app uses that to defer its `<Entry>__init()` until
// after the terminal knows its real dimensions, otherwise paint
// happens at the default 24×80 then gets resized away.
//
// Keyboard input: an invisible KeyboardCapture overlay sits in the
// background as a first responder, mapping UIPress events to Oberon
// codes via oc_dispatch_key. SwiftUI's own .onKeyPress is unreliable
// on iPad — focus state doesn't propagate the way it does on macOS.

import SwiftUI
import UIKit
import OberonRuntime

public struct TerminalView: View {
    @ObservedObject private var state = TerminalState.shared
    @State private var hasReady = false

    /// Monospaced font used for cell measurement and rendering. The
    /// 3270 font is the canonical match for the palette; the host app
    /// should register it (Fonts/UIAppFonts) and pass its name here.
    /// Defaults to the system monospaced face.
    public let fontName: String?
    public let fontSize: CGFloat
    /// Fires once after the first stable resize. The host calls
    /// `<Entry>__init()` (or any Oberon-side bootstrap) here so the
    /// initial paint happens at the real terminal dimensions, not
    /// the 24×80 defaults that get overwritten by GeometryReader's
    /// later resize.
    public let onReady: (() -> Void)?

    public init(fontName: String? = nil,
                fontSize: CGFloat = 16,
                onReady: (() -> Void)? = nil) {
        self.fontName = fontName
        self.fontSize = fontSize
        self.onReady  = onReady
    }

    public var body: some View {
        GeometryReader { proxy in
            let metrics = cellMetrics()
            let cols = max(1, Int(proxy.size.width  / metrics.width))
            let rows = max(1, Int(proxy.size.height / metrics.height))
            ZStack(alignment: .topLeading) {
                // First responder for hardware keyboard events. Has
                // no visible content; lives behind the cell grid.
                KeyboardCapture()
                    .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<state.displayed.count, id: \.self) { r in
                        rowView(r, metrics: metrics)
                            .frame(height: metrics.height, alignment: .leading)
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .background(Color.black)
            .foregroundColor(Palette.color(4) ?? .green)   // ColorGreen as default
            .font(.system(size: fontSize, design: .monospaced))
            .onAppear {
                state.resize(rows: rows, cols: cols)
                fireReadyIfStable(rows: rows, cols: cols)
            }
            .onChange(of: proxy.size) { _, _ in
                state.resize(rows: rows, cols: cols)
                fireReadyIfStable(rows: rows, cols: cols)
                // Resize doesn't wipe content (the new resize keeps
                // cells in place), but the Oberon side has no idea
                // its grid changed shape — its handleKey-driven
                // Refresh is the only repaint trigger. Dispatch
                // Ctrl-L: oed's handler binds it to "clear status"
                // and unconditionally calls Refresh afterwards, so
                // it re-lays out for the new dimensions without
                // side effects on buffer state.
                if hasReady {
                    oc_dispatch_key(12)
                }
            }
        }
    }

    private func fireReadyIfStable(rows: Int, cols: Int) {
        // Wait until we have realistic dimensions before triggering
        // the host's bootstrap — initial GeometryReader pass can
        // report 0×0 / 1×1 which would have the Oberon side paint
        // a useless layout that gets immediately resized over.
        guard !hasReady, rows > 1, cols > 1 else { return }
        hasReady = true
        onReady?()
    }

    @ViewBuilder
    private func rowView(_ r: Int, metrics: (width: CGFloat, height: CGFloat)) -> some View {
        let row = state.displayed[r]
        ZStack(alignment: .topLeading) {
            // Per-cell styling via AttributedString: each cell becomes
            // a one-character span carrying its fg / bg / bold / italic
            // / underline / reverse-video attributes. Monospaced font
            // keeps widths uniform across bold + italic.
            Text(attributedRow(row))
                .lineLimit(1)
                .truncationMode(.tail)

            // Cursor: solid block over the cell at (curCol, curRow).
            // .blendMode(.difference) inverts the underlying glyph so
            // the character reads through the cursor — classic terminal
            // block-cursor look.
            if state.cursorVisible && r == state.curRow {
                Rectangle()
                    .fill(Palette.color(4) ?? .green)
                    .frame(width: metrics.width, height: metrics.height)
                    .offset(x: CGFloat(state.curCol) * metrics.width)
                    .blendMode(.difference)
            }
        }
    }

    private func attributedRow(_ row: [Cell]) -> AttributedString {
        let defaultFg = Palette.color(4) ?? Color.green   // ColorGreen
        let defaultBg = Color.black
        var out = AttributedString("")
        for cell in row {
            var span = AttributedString(String(cell.ch))
            let cellFg = Palette.color(cell.fg) ?? defaultFg
            let cellBg = Palette.color(cell.bg) ?? defaultBg
            let (fg, bg) = cell.attr.contains(.reverse)
                ? (cellBg, cellFg)
                : (cellFg, cellBg)
            span.foregroundColor = fg
            span.backgroundColor = bg

            var font: Font = .system(size: fontSize, design: .monospaced)
            if cell.attr.contains(.bold)   { font = font.weight(.bold) }
            if cell.attr.contains(.italic) { font = font.italic() }
            span.font = font

            if cell.attr.contains(.underline) {
                span.underlineStyle = .single
            }
            out.append(span)
        }
        return out
    }

    private func cellMetrics() -> (width: CGFloat, height: CGFloat) {
        // Rough metric — UIFont's monospaced-digit width is close
        // enough for layout. The actual SwiftUI Text uses kerning
        // that matches, since we set the same font.
        let font: UIFont = {
            if let name = fontName, let f = UIFont(name: name, size: fontSize) {
                return f
            }
            return UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }()
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let w = ("M" as NSString).size(withAttributes: attrs).width
        let h = font.lineHeight
        return (w, h)
    }
}
