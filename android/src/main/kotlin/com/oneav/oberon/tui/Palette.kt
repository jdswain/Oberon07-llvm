// IBM 3270-style 8-colour palette. Index matches TUI.ColorBlack..
// ColorWhite; -1 means "terminal default" — Compose callers
// substitute their own foreground/background. Matches the wasm
// tui-shim's PALETTE and the iOS Palette so programs render
// identically across all three hosts.

package com.oneav.oberon.tui

import androidx.compose.ui.graphics.Color

object Palette {
    val colors: List<Color> = listOf(
        Color(0xFF000000),  // 0 Black
        Color(0xFF0050FF),  // 1 Blue
        Color(0xFFFF3030),  // 2 Red
        Color(0xFFFF66CC),  // 3 Pink
        Color(0xFF00CC66),  // 4 Green
        Color(0xFF00CCCC),  // 5 Turquoise
        Color(0xFFFFD000),  // 6 Yellow
        Color(0xFFF0F0F0),  // 7 White
    )

    fun color(i: Int): Color? = if (i in 0..7) colors[i] else null

    val defaultFg: Color = colors[4]  // ColorGreen — phosphor terminal look
    val defaultBg: Color = colors[0]  // Black
}
