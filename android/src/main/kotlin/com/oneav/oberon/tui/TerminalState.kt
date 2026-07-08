// TerminalState — observable model behind the Compose TerminalView.
//
// Mirrors the iOS TerminalState: two-buffer cell grid, `putChar`
// mutates `pending`, `flush` commits to `displayed`, Compose observes
// `frame`. All access is expected on the UI thread; JNI upcalls
// from Oberon C code run there so there's no explicit locking.

package com.oneav.oberon.tui

import androidx.compose.runtime.mutableStateOf

/** Display attribute bits — must match TUI.Mod's AttrReverse /
 *  Bold / Italic / Underline. */
object CellAttr {
    const val REVERSE   = 1
    const val BOLD      = 2
    const val ITALIC    = 4
    const val UNDERLINE = 8
}

/** One screen cell. `fg`/`bg` are indices into the 3270 palette
 *  (0..7) or -1 for "terminal default". */
data class Cell(
    val ch:   Char,
    val attr: Int,
    val fg:   Int,
    val bg:   Int,
) {
    companion object {
        val BLANK = Cell(ch = ' ', attr = 0, fg = -1, bg = -1)
    }
}

object TerminalState {
    /** Grid dimensions in cells. Updated by TerminalView's geometry
     *  observer before Oberon reads via tuiRows / tuiCols. */
    var rows: Int = 24
        private set
    var cols: Int = 80
        private set

    /** Pending state being written by Oberon; committed to
     *  `displayed` on flush. The two-buffer scheme avoids
     *  partial-frame flicker during a multi-call redraw. */
    private var pending: Array<Array<Cell>> = makeGrid(rows, cols)

    /** What Compose renders. Compose diffs the two-dimensional
     *  Array reference; we allocate a fresh grid on flush so the
     *  state observer definitely fires. */
    val displayed = mutableStateOf(pending)

    var curCol: Int = 0
        private set
    var curRow: Int = 0
        private set
    private var curAttr: Int = 0
    private var curFg:   Int = -1
    private var curBg:   Int = -1
    val cursorVisible = mutableStateOf(true)

    /** Bumped on every flush so views that key off it can force
     *  redraws without diffing the full grid. */
    val frame = mutableStateOf(0)

    init { reset() }

    fun reset() {
        pending = makeGrid(rows, cols)
        displayed.value = pending
        curCol = 0; curRow = 0
        curAttr = 0; curFg = -1; curBg = -1
        cursorVisible.value = true
    }

    /** Grow / shrink in place — never wipes, so Compose's initial
     *  layout passes don't blank what Oberon may have already
     *  painted. Matches the iOS resize semantics. */
    fun resize(newRows: Int, newCols: Int) {
        val r = maxOf(1, newRows)
        val c = maxOf(1, newCols)
        if (r == rows && c == cols) return
        val next = Array(r) { row ->
            Array(c) { col ->
                if (row < pending.size && col < pending[row].size)
                    pending[row][col]
                else
                    Cell.BLANK
            }
        }
        pending = next
        rows = r; cols = c
        displayed.value = pending
        if (curRow >= rows) curRow = rows - 1
        if (curCol >= cols) curCol = cols - 1
    }

    fun putChar(ch: Char) {
        if (curRow !in 0 until rows || curCol !in 0 until cols) return
        pending[curRow][curCol] = Cell(ch, curAttr, curFg, curBg)
        curCol++
        if (curCol >= cols) curCol = cols - 1
    }

    fun clear() {
        for (r in 0 until rows) for (c in 0 until cols) {
            pending[r][c] = Cell.BLANK
        }
        curCol = 0; curRow = 0
    }

    fun clearLine() {
        if (curRow !in 0 until rows) return
        for (c in 0 until cols) pending[curRow][c] = Cell.BLANK
    }

    fun moveTo(col: Int, row: Int) {
        curCol = col.coerceIn(0, cols - 1)
        curRow = row.coerceIn(0, rows - 1)
    }

    fun setAttr(a: Int) { curAttr = a }
    fun setFg(c: Int)   { curFg = if (c in -1..7) c else -1 }
    fun setBg(c: Int)   { curBg = if (c in -1..7) c else -1 }
    fun setCursorVisible(v: Boolean) { cursorVisible.value = v }

    fun flush() {
        // Allocate a fresh outer array so Compose's reference-based
        // observation triggers. Row references are shared with
        // pending — the next paint operation mutates in place and
        // the next flush produces a fresh outer snapshot.
        val snapshot = Array(rows) { pending[it] }
        displayed.value = snapshot
        frame.value += 1
    }

    private fun makeGrid(r: Int, c: Int): Array<Array<Cell>> =
        Array(r) { Array(c) { Cell.BLANK } }
}

/** Polling-path key queue. Event-driven dispatch (via
 *  OberonBridge.ocDispatchKey) bypasses it; if the program
 *  registers a key handler, this stays empty. */
object KeyQueue {
    private val queue = ArrayDeque<Int>()
    fun push(code: Int) { queue.addLast(code) }
    fun pop(): Int? = if (queue.isEmpty()) null else queue.removeFirst()
}
