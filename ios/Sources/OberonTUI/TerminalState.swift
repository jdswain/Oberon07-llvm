// TerminalState — observable model behind the SwiftUI TerminalView.
//
// The Oberon-side TUI calls (Init / Clear / MoveTo / Write / Flush)
// route through TerminalShim.swift's @_cdecl entry points and mutate
// this shared instance; SwiftUI observes the @Published properties
// and redraws. Mirrors the role of the web tui-shim's local `cells`
// / `curRow` / `curCol` state — single-host invariant: there is one
// terminal per process.

import SwiftUI

/// Display attribute bits — must match TUI.Mod's AttrReverse / Bold /
/// Italic / Underline.
public struct CellAttr: OptionSet, Sendable {
    public let rawValue: Int32
    public init(rawValue: Int32) { self.rawValue = rawValue }
    public static let reverse   = CellAttr(rawValue: 1)
    public static let bold      = CellAttr(rawValue: 2)
    public static let italic    = CellAttr(rawValue: 4)
    public static let underline = CellAttr(rawValue: 8)
}

/// One screen cell. `fg`/`bg` are indices into the 3270 palette
/// (0..7) or -1 for "terminal default".
public struct Cell: Sendable, Equatable {
    public var ch:   Character
    public var attr: CellAttr
    public var fg:   Int8       // -1 = default
    public var bg:   Int8

    public static let blank = Cell(ch: " ", attr: [], fg: -1, bg: -1)
}

/// Shared terminal state. The shim mutates this from the main thread
/// (Oberon callbacks run on the same thread that dispatches keys, i.e.
/// the main thread under SwiftUI). The @Published wrappers trigger
/// SwiftUI redraws when `flush` advances `frame`.
@MainActor
public final class TerminalState: ObservableObject {
    public static let shared = TerminalState()

    /// Grid dimensions in cells. Updated by TerminalView's geometry
    /// reader before any Oberon code runs and on every size change;
    /// the ios_tui_rows / ios_tui_cols externs read these.
    public var rows: Int = 24
    public var cols: Int = 80

    /// Pending state being written by Oberon. The view reads from
    /// `displayed` (committed at flush); this two-buffer scheme
    /// avoids partial-frame flicker during a multi-call redraw.
    public var pending:   [[Cell]] = []
    @Published public var displayed: [[Cell]] = []

    public var curCol = 0
    public var curRow = 0
    public var curAttr: CellAttr = []
    public var curFg:   Int8 = -1
    public var curBg:   Int8 = -1
    @Published public var cursorVisible = true

    /// Bumped on every flush so views that key off it can force
    /// updates without diffing the full grid.
    @Published public var frame: Int = 0

    private init() {
        reset()
    }

    public func reset() {
        pending   = Self.makeGrid(rows: rows, cols: cols)
        displayed = pending
        curCol = 0; curRow = 0
        curAttr = []; curFg = -1; curBg = -1
    }

    /// Resize the grid in-place. Existing cells survive where they
    /// still fit; new rows / columns blank-fill. Critical for the
    /// startup race: SwiftUI's GeometryReader fires resize once or
    /// twice during initial layout, and we don't want to wipe out
    /// whatever the Oberon side may have already painted.
    public func resize(rows: Int, cols: Int) {
        let newRows = max(1, rows)
        let newCols = max(1, cols)
        guard newRows != self.rows || newCols != self.cols else { return }

        if newRows > pending.count {
            let extra = Array(repeating: Array(repeating: Cell.blank, count: newCols),
                              count: newRows - pending.count)
            pending.append(contentsOf: extra)
        } else if newRows < pending.count {
            pending = Array(pending.prefix(newRows))
        }
        for r in 0..<pending.count {
            if pending[r].count < newCols {
                pending[r].append(contentsOf:
                    Array(repeating: Cell.blank, count: newCols - pending[r].count))
            } else if pending[r].count > newCols {
                pending[r] = Array(pending[r].prefix(newCols))
            }
        }

        self.rows = newRows
        self.cols = newCols
        displayed = pending
        if curRow >= self.rows { curRow = self.rows - 1 }
        if curCol >= self.cols { curCol = self.cols - 1 }
    }

    public func putChar(_ ch: Character) {
        guard curRow >= 0, curRow < rows, curCol >= 0, curCol < cols else { return }
        pending[curRow][curCol] = Cell(ch: ch, attr: curAttr, fg: curFg, bg: curBg)
        curCol += 1
        if curCol >= cols { curCol = cols - 1 }
    }

    public func clear() {
        for r in 0..<rows {
            for c in 0..<cols {
                pending[r][c] = .blank
            }
        }
        curCol = 0; curRow = 0
    }

    public func clearLine() {
        guard curRow >= 0, curRow < rows else { return }
        for c in 0..<cols {
            pending[curRow][c] = .blank
        }
    }

    public func moveTo(col: Int, row: Int) {
        curCol = max(0, min(col, cols - 1))
        curRow = max(0, min(row, rows - 1))
    }

    public func flush() {
        displayed = pending
        frame &+= 1
    }

    private static func makeGrid(rows: Int, cols: Int) -> [[Cell]] {
        Array(repeating: Array(repeating: Cell.blank, count: cols), count: rows)
    }
}
