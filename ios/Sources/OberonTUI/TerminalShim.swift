// TerminalShim — @_cdecl entry points the Oberon TUI runtime
// sidecar (runtime/ios/TUI_rt.c) calls into. Each function maps a
// single TUI primitive onto TerminalState.shared. Names and ABI
// must stay in sync with the externs declared in TUI_rt.c.
//
// All entry points run on the main actor because TerminalState is
// @MainActor-isolated. The runtime sidecar (and the Oberon code it
// hosts) is single-threaded under the SwiftUI event loop, so the
// implicit dispatch is correct without explicit await — Oberon never
// re-enters from a background thread.

import Foundation

@MainActor
private let state = TerminalState.shared

// MARK: - Lifecycle

@_cdecl("ios_tui_init")
public func ios_tui_init() {
    MainActor.assumeIsolated { state.reset() }
}

@_cdecl("ios_tui_shutdown")
public func ios_tui_shutdown() {
    // No teardown — the SwiftUI host owns the view lifecycle.
}

@_cdecl("ios_tui_rows")
public func ios_tui_rows() -> Int32 {
    MainActor.assumeIsolated { Int32(state.rows) }
}

@_cdecl("ios_tui_cols")
public func ios_tui_cols() -> Int32 {
    MainActor.assumeIsolated { Int32(state.cols) }
}

// MARK: - Screen mutation

@_cdecl("ios_tui_clear")
public func ios_tui_clear() {
    MainActor.assumeIsolated { state.clear() }
}

@_cdecl("ios_tui_clear_line")
public func ios_tui_clear_line() {
    MainActor.assumeIsolated { state.clearLine() }
}

@_cdecl("ios_tui_move_to")
public func ios_tui_move_to(_ col: Int32, _ row: Int32) {
    MainActor.assumeIsolated { state.moveTo(col: Int(col), row: Int(row)) }
}

@_cdecl("ios_tui_show_cursor")
public func ios_tui_show_cursor() {
    MainActor.assumeIsolated { state.cursorVisible = true }
}

@_cdecl("ios_tui_hide_cursor")
public func ios_tui_hide_cursor() {
    MainActor.assumeIsolated { state.cursorVisible = false }
}

@_cdecl("ios_tui_set_attr")
public func ios_tui_set_attr(_ attr: Int32) {
    MainActor.assumeIsolated { state.curAttr = CellAttr(rawValue: attr) }
}

@_cdecl("ios_tui_set_fg")
public func ios_tui_set_fg(_ color: Int32) {
    MainActor.assumeIsolated { state.curFg = Int8(clamping: color) }
}

@_cdecl("ios_tui_set_bg")
public func ios_tui_set_bg(_ color: Int32) {
    MainActor.assumeIsolated { state.curBg = Int8(clamping: color) }
}

@_cdecl("ios_tui_write_char")
public func ios_tui_write_char(_ ch: Int32) {
    MainActor.assumeIsolated {
        guard let scalar = Unicode.Scalar(UInt32(ch & 0xFF)) else { return }
        state.putChar(Character(scalar))
    }
}

@_cdecl("ios_tui_write_str")
public func ios_tui_write_str(_ p: UnsafePointer<CChar>?, _ n: Int32) {
    guard let p = p, n > 0 else { return }
    let buf = UnsafeBufferPointer(start: p, count: Int(n))
    MainActor.assumeIsolated {
        for i in 0..<Int(n) {
            let byte = UInt8(bitPattern: buf[i])
            if byte == 0 { break }   // Oberon strings are NUL-terminated
            if byte == 0x0A {        // '\n'
                state.moveTo(col: 0, row: state.curRow + 1)
                continue
            }
            if let scalar = Unicode.Scalar(UInt32(byte)) {
                state.putChar(Character(scalar))
            }
        }
    }
}

@_cdecl("ios_tui_flush")
public func ios_tui_flush() {
    MainActor.assumeIsolated { state.flush() }
}

// MARK: - Input (polling path)

/// Polling-path input. The event-driven path (oc_dispatch_key, called
/// from TerminalView's keyboard handler) is preferred; this exists
/// only for code that reads keys directly via TUI.ReadKey. Returns 0
/// when the queue is empty.
@_cdecl("ios_tui_read_key")
public func ios_tui_read_key() -> Int32 {
    MainActor.assumeIsolated {
        KeyQueue.shared.pop().map(Int32.init) ?? 0
    }
}

/// Queue for the polling-path. The event-driven dispatch (via
/// oc_dispatch_key) bypasses it; if the program registers a key
/// handler, the queue stays empty.
@MainActor
final class KeyQueue {
    static let shared = KeyQueue()
    private var queue: [Int] = []
    func push(_ code: Int) { queue.append(code) }
    func pop() -> Int? { queue.isEmpty ? nil : queue.removeFirst() }
}
