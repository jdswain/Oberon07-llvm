// KeyCodes.swift — UIKey → Oberon code mapping for the iOS host.
//
// Hardware keyboard events on iOS / iPadOS come through UIResponder's
// pressesBegan as a Set<UIPress>; each press carries a UIKey. We
// translate to the integer codes the Oberon TUI module expects
// (mirrors web/src/tui-shim.ts):
//
//   1..26    Ctrl + letter
//   9 / 13 / 27 / 127  Tab / Enter / Esc / Backspace
//   32..126  printable ASCII
//   256..264 ArrowUp/Down/Left/Right, Home, End, PageUp, PageDown, Delete
//   290..299 Meta-< Meta-> Meta-f b a e w y n p
//
// Returns nil for unmapped keys so the caller passes them up the
// responder chain.

import UIKit

public func mapUIKey(_ key: UIKey) -> Int32? {
    // Special keys via keyCode (independent of modifier state).
    switch key.keyCode {
    case .keyboardUpArrow:           return 256
    case .keyboardDownArrow:         return 257
    case .keyboardLeftArrow:         return 258
    case .keyboardRightArrow:        return 259
    case .keyboardHome:              return 260
    case .keyboardEnd:               return 261
    case .keyboardPageUp:            return 262
    case .keyboardPageDown:          return 263
    case .keyboardDeleteOrBackspace: return 127
    case .keyboardDeleteForward:     return 264
    case .keyboardReturnOrEnter:     return 13
    case .keyboardTab:               return 9
    case .keyboardEscape:            return 27
    default: break
    }

    let mods  = key.modifierFlags
    let plain = key.charactersIgnoringModifiers
    guard let ch = plain.first else { return nil }

    // Meta (Alt / Option) + letter — bindings oed defines via KeyMeta*.
    if mods.contains(.alternate) {
        switch ch {
        case "<": return 290
        case ">": return 291
        case "f": return 292
        case "b": return 293
        case "a": return 294
        case "e": return 295
        case "w": return 296
        case "y": return 297
        case "n": return 298
        case "p": return 299
        default: break
        }
    }

    // Ctrl + letter → 1..26.
    if mods.contains(.control) {
        if let scalar = ch.uppercased().unicodeScalars.first, scalar.isASCII {
            return Int32(scalar.value & 0x1F)
        }
    }

    // Printable ASCII passes through. Use `characters` (which honours
    // shift) for the final value so 'A' vs 'a' / '1' vs '!' is right.
    if let scalar = key.characters.unicodeScalars.first,
       scalar.isASCII, scalar.value >= 32, scalar.value < 127 {
        return Int32(scalar.value)
    }

    return nil
}
