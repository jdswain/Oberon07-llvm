// TerminalView — Jetpack Compose cell-grid view backed by
// TerminalState. Scaffold-grade: renders each row as a single
// AnnotatedString whose spans carry the cell's fg / bg / attr; a
// cursor overlay uses BlendMode.Difference to invert the glyph
// underneath. Matches the iOS TerminalView so paint looks the same
// across hosts.
//
// Keyboard: Modifier.onPreviewKeyEvent captures hardware key
// events and dispatches into OberonBridge.ocDispatchKey. We claim
// focus with FocusRequester so the view receives keys immediately
// on first composition. Autorepeat: Android's dispatch driver
// re-fires KeyEventType.KeyDown for held keys automatically at the
// system rate, so we don't run a Timer of our own (unlike iOS).
//
// Geometry: BoxWithConstraints measures available space, we
// compute cellW/cellH from a monospaced font metric, and report
// rows/cols to TerminalState before any Oberon code reads them.
// After the first stable resize we fire `onReady`, and the host
// calls its Oberon `<Entry>__init()` there so the initial paint
// lands at the real dimensions.

package com.oneav.oberon.tui

import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.max

@Composable
fun TerminalView(
    fontSize: Int = 16,
    onReady: (() -> Unit)? = null,
) {
    val displayed by TerminalState.displayed
    val cursorVisible by TerminalState.cursorVisible
    val focusRequester = remember { FocusRequester() }
    var hasReady by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) { focusRequester.requestFocus() }

    BoxWithConstraints(
        modifier = Modifier
            .fillMaxSize()
            .background(Palette.defaultBg)
            .focusRequester(focusRequester)
            .focusable()
            .onPreviewKeyEvent { evt ->
                // Only dispatch on KeyDown; Android re-fires KeyDown
                // for autorepeat so we don't need a Timer.
                if (evt.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
                val code = mapKeyEvent(evt) ?: return@onPreviewKeyEvent false
                OberonBridge.ocDispatchKey(code)
                true
            }
    ) {
        val density = LocalDensity.current
        val cellWSp = fontSize.sp
        val measurer = rememberTextMeasurer()
        val monoStyle = TextStyle(
            fontFamily = FontFamily.Monospace,
            fontSize   = cellWSp,
            color      = Palette.defaultFg,
        )
        val probe = remember(fontSize) { measurer.measure(AnnotatedString("M"), monoStyle) }
        val cellW: Dp = with(density) { probe.size.width.toDp() }
        val cellH: Dp = with(density) { probe.size.height.toDp() }

        val cols = max(1, (maxWidth  / cellW).toInt())
        val rows = max(1, (maxHeight / cellH).toInt())

        LaunchedEffect(cols, rows) {
            TerminalState.resize(rows, cols)
            if (!hasReady && cols > 1 && rows > 1) {
                hasReady = true
                onReady?.invoke()
            } else if (hasReady) {
                // Signal Oberon side to repaint at the new size —
                // Ctrl-L (12) is bound to "clear status" in oed and
                // handleKey unconditionally Refreshes after.
                OberonBridge.ocDispatchKey(12)
            }
        }

        Column {
            for (r in displayed.indices) {
                RowView(
                    row = displayed[r],
                    isCursorRow = cursorVisible && r == TerminalState.curRow,
                    curCol = TerminalState.curCol,
                    cellW = cellW,
                    cellH = cellH,
                    style = monoStyle,
                )
            }
        }
    }
}

@Composable
private fun RowView(
    row: Array<Cell>,
    isCursorRow: Boolean,
    curCol: Int,
    cellW: Dp,
    cellH: Dp,
    style: TextStyle,
) {
    val text = buildAnnotatedString {
        for (cell in row) {
            val cellFg = Palette.color(cell.fg) ?: Palette.defaultFg
            val cellBg = Palette.color(cell.bg) ?: Palette.defaultBg
            val (fg, bg) =
                if ((cell.attr and CellAttr.REVERSE) != 0) cellBg to cellFg
                else cellFg to cellBg
            val weight = if ((cell.attr and CellAttr.BOLD)      != 0) FontWeight.Bold   else FontWeight.Normal
            val slant  = if ((cell.attr and CellAttr.ITALIC)    != 0) FontStyle.Italic  else FontStyle.Normal
            val decor  = if ((cell.attr and CellAttr.UNDERLINE) != 0) TextDecoration.Underline else TextDecoration.None
            withStyle(
                SpanStyle(
                    color           = fg,
                    background      = bg,
                    fontWeight      = weight,
                    fontStyle       = slant,
                    textDecoration  = decor,
                    fontFamily      = FontFamily.Monospace,
                )
            ) { append(cell.ch.toString()) }
        }
    }
    Box(Modifier.height(cellH)) {
        BasicText(
            text     = text,
            style    = style,
            maxLines = 1,
            overflow = TextOverflow.Clip,
        )
        if (isCursorRow) {
            Box(
                Modifier
                    .offset(x = cellW * curCol)
                    .size(width = cellW, height = cellH)
                    .drawWithContent {
                        // Solid cursor block; BlendMode.Difference
                        // inverts the glyph underneath so the
                        // character reads through.
                        drawContent()
                        drawRect(
                            brush = SolidColor(Palette.defaultFg),
                            blendMode = BlendMode.Difference,
                        )
                    }
            )
        }
    }
}
