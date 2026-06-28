// IBM 3270-style 8-colour palette. Index matches TUI.ColorBlack..
// ColorWhite; -1 means "terminal default" and falls back to the
// terminal's foreground/background. Matches web/src/tui-shim.ts so
// programs render identically across hosts.

import SwiftUI

public enum Palette {
    public static let colors: [Color] = [
        Color(red: 0.00, green: 0.00, blue: 0.00),   // 0 Black
        Color(red: 0.00, green: 0.31, blue: 1.00),   // 1 Blue
        Color(red: 1.00, green: 0.19, blue: 0.19),   // 2 Red
        Color(red: 1.00, green: 0.40, blue: 0.80),   // 3 Pink
        Color(red: 0.00, green: 0.80, blue: 0.40),   // 4 Green
        Color(red: 0.00, green: 0.80, blue: 0.80),   // 5 Turquoise
        Color(red: 1.00, green: 0.82, blue: 0.00),   // 6 Yellow
        Color(red: 0.94, green: 0.94, blue: 0.94),   // 7 White
    ]

    /// Map a palette index to a SwiftUI Color, or `nil` for default
    /// (caller substitutes its own foreground/background).
    public static func color(_ i: Int8) -> Color? {
        guard i >= 0, i < 8 else { return nil }
        return colors[Int(i)]
    }
}
