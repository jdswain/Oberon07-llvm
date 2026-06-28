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
// space and reports rows/cols back to TerminalState before any
// Oberon code reads them via ios_tui_rows / ios_tui_cols.

import SwiftUI
import UIKit

public struct TerminalView: View {
    @ObservedObject private var state = TerminalState.shared

    /// Monospaced font used for cell measurement and rendering. The
    /// 3270 font is the canonical match for the palette; the host app
    /// should register it (Fonts/UIAppFonts) and pass its name here.
    /// Defaults to the system monospaced face.
    public let fontName: String?
    public let fontSize: CGFloat

    public init(fontName: String? = nil, fontSize: CGFloat = 16) {
        self.fontName = fontName
        self.fontSize = fontSize
    }

    public var body: some View {
        GeometryReader { proxy in
            let metrics = cellMetrics()
            let cols = max(1, Int(proxy.size.width  / metrics.width))
            let rows = max(1, Int(proxy.size.height / metrics.height))
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<state.displayed.count, id: \.self) { r in
                    rowView(r)
                        .frame(height: metrics.height, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .background(Color.black)
            .foregroundColor(Palette.color(4) ?? .green)   // ColorGreen as default
            .font(.system(size: fontSize, design: .monospaced))
            .onAppear        { state.resize(rows: rows, cols: cols) }
            .onChange(of: proxy.size) { _ in state.resize(rows: rows, cols: cols) }
        }
    }

    @ViewBuilder
    private func rowView(_ r: Int) -> some View {
        let row = state.displayed[r]
        // One Text with concatenated characters keeps things simple.
        // Per-cell styling (fg / bg / attr) will need a richer build
        // (HStack of Texts or a Canvas). For now we render plain chars
        // so the scaffold compiles and renders something visible.
        Text(String(row.map { $0.ch }))
            .lineLimit(1)
            .truncationMode(.tail)
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
