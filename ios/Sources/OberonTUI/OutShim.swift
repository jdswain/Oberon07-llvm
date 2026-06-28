// OutShim — @_cdecl entry points for the Out runtime module.
//
// On wasm and posix Out targets stdout. On iOS there is no stdout
// the user can see, so we route Out.* into the terminal so plain
// Out.WriteString programs (the simplest Oberon hello-world) print
// to the same surface the program sees as the TUI.
//
// Programs that want a separate log surface can add a second shim
// target later; for the scaffold the simplest unified behaviour wins.

import Foundation

@_cdecl("ios_out_write")
public func ios_out_write(_ ch: Int32) {
    ios_tui_write_char(ch)
}

@_cdecl("ios_out_writestr")
public func ios_out_writestr(_ s: UnsafePointer<CChar>?, _ n: Int32) {
    ios_tui_write_str(s, n)
}

@_cdecl("ios_out_writeint")
public func ios_out_writeint(_ x: Int32) {
    let s = String(x)
    s.withCString { ptr in
        ios_tui_write_str(ptr, Int32(s.utf8.count))
    }
}

@_cdecl("ios_out_ln")
public func ios_out_ln() {
    ios_tui_write_char(0x0A)   // '\n'
    ios_tui_flush()             // matches posix runtime: line-buffered
}
