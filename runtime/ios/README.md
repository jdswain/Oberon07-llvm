# iOS runtime

Runtime modules for the `arm64-apple-ios` / `arm64-apple-ios-simulator`
targets. Same shape as `runtime/wasm/`: the `.Mod` files give Oberon
importers a typed signature with empty (weak-linkage) bodies, and the
`_rt.c` sidecars override those bodies and forward to host externs
implemented by the embedding app.

## Selecting this runtime

The compiler picks the flavour from the `-target` triple. Anything
containing `-ios` (device, simulator, with or without min-version
suffix) routes to `runtime/ios/`:

    bin/oc -target arm64-apple-ios15.0           Tiny.Mod  # device
    bin/oc -target arm64-apple-ios-simulator     Tiny.Mod  # Apple-silicon simulator
    bin/oc -target x86_64-apple-ios-simulator    Tiny.Mod  # Intel simulator

Use a versioned form like `arm64-apple-ios15.0` to avoid the linker
warning "no platform load command found …" — the version is stamped
into the IR and Mach-O so the eventual app linker picks it up.

The `oc` driver does **not** link iOS binaries. Compile each Oberon
module to a `.o` here, then link the `.o` set into the iOS app from
Xcode (oed's iOS scheme owns this).

## Host extern contract

Each `_rt.c` file declares the externs Swift must provide. They use
plain C ABI; the Swift side exposes matching `@_cdecl` functions:

| C extern                                  | Swift signature (sketch)                              |
| ----------------------------------------- | ----------------------------------------------------- |
| `ios_tui_init`                            | `@_cdecl("ios_tui_init") func iosTuiInit()`           |
| `ios_tui_rows` / `ios_tui_cols`           | `() -> Int32`                                         |
| `ios_tui_clear` / `ios_tui_clear_line`    | `() -> Void`                                          |
| `ios_tui_move_to(col, row)`               | `(Int32, Int32) -> Void`                              |
| `ios_tui_show_cursor` / `_hide_cursor`    | `() -> Void`                                          |
| `ios_tui_set_attr` / `_fg` / `_bg`        | `(Int32) -> Void`                                     |
| `ios_tui_write_char(ch)`                  | `(Int32) -> Void`                                     |
| `ios_tui_write_str(ptr, len)`             | `(UnsafePointer<CChar>?, Int32) -> Void`              |
| `ios_tui_flush`                           | `() -> Void`                                          |
| `ios_tui_read_key`                        | `() -> Int32` (0 = no key queued)                     |
| `ios_out_write` / `_writestr` / `_writeint` / `_ln` | mirror — same shape as TUI write ops        |
| `ios_env_cwd(out, out_len)`               | `(UnsafeMutablePointer<CChar>?, Int32) -> Void`       |
| `ios_env_base_path(out, out_len)`         | same                                                  |

The Oberon side calls `TUI__SetKeyHandler(handler)` then `TUI__Run()`;
the Swift host then drives keyboard events by calling
`oc_dispatch_key(code)` (exported from `TUI_rt.c`) on each keystroke,
which invokes the registered Oberon handler. This is the event-driven
path — the polling `ReadKey` path is supported but iOS apps will
prefer event-driven so the UI thread never blocks.

Cell coordinates and the colour palette match the wasm port (3270
ordering: black / blue / red / pink / green / turquoise / yellow /
white = 0..7). The Swift cell-grid view should mirror what the web
`tui-shim.ts` does — fixed cell size, per-cell `<span>`-equivalent
with fg / bg / attr.

## What's stubbed at runtime

- `Files.Mod` — empty Oberon bodies. `Old` / `New` return `NIL`,
  reads / writes are no-ops, `Exists` returns `0`. Enough to link
  oed against the iOS runtime; replace with a `Files_rt.c` that
  forwards to Swift / FileManager when the iCloud-container wiring
  lands.
- `Env.ArgCount` returns 0, `Env.Arg` returns empty (iOS apps have
  no argv).
- `Controls.Mod` is pure Oberon — no host hooks, no `_rt.c` needed.

## What's missing here (lives in the oed repo)

- The Xcode project, app target, entitlements.
- Swift implementations of the `ios_tui_*`, `ios_out_*`,
  `ios_env_*` externs.
- The SwiftUI terminal view that backs `ios_tui_*` (analogous to
  `web/src/tui-shim.ts`).
- The ubiquity-container wiring once `Files_rt.c` is added.
