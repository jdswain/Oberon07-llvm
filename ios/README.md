# OberonTUI — iOS host package

Swift Package Manager (SPM) package providing the iOS host for
Oberon programs compiled with `oc -target arm64-apple-ios*`.
Parallel to `oc/web/`: where the wasm port runs a `<div>`-grid in
the browser driven by `web/src/tui-shim.ts`, this package runs a
SwiftUI cell-grid view driven by `Sources/OberonTUI/TerminalShim.swift`.

## Targets

- **OberonTUI** — Swift target with:
  - `TerminalState` — shared `@MainActor` observable that holds the
    cell grid, cursor, attribute state. One per process.
  - `TerminalView` — SwiftUI view that renders `TerminalState`.
    Measures the available area with `GeometryReader` and reports
    the resulting `rows` / `cols` back into the state before any
    Oberon code reads them.
  - `TerminalShim` — `@_cdecl` exports `ios_tui_*` matching the
    externs declared in `oc/runtime/ios/TUI_rt.c`.
  - `OutShim`, `EnvShim` — same pattern for `Out.*` and `Env.*`.
  - `Palette` — 8-colour 3270-style palette, indices matching
    `TUI.ColorBlack..ColorWhite` from the Oberon side.
- **OberonRuntime** — C target carrying `OberonRuntime.h`, the
  bridging header declaring the small runtime surface Swift calls
  *into* (`oc_dispatch_key`, `oc_set_args`). The Oberon side is
  defined by `oc/runtime/ios/TUI_rt.c`'s `oc_dispatch_key`.

## Consuming app — build recipe

```swift
// Package.swift in the app, or "Add Package Dependency" in Xcode.
dependencies: [
    .package(path: "../oc/ios"),
],
targets: [
    .target(name: "MyApp",
            dependencies: [
              .product(name: "OberonTUI",     package: "ios"),
              .product(name: "OberonRuntime", package: "ios"),
            ])
]
```

```swift
// MyAppApp.swift
import SwiftUI
import OberonTUI
import OberonRuntime

@main
struct MyAppApp: App {
    init() {
        oc_set_args(0, nil)        // iOS has no argv
        MyApp__init()              // declared in your bridging header
    }
    var body: some Scene {
        WindowGroup { TerminalView() }
    }
}
```

The app must also:

1. Compile its Oberon sources with
   `oc -target arm64-apple-ios15.0 *.Mod` (or the simulator triple)
   producing `*.o` files.
2. Compile the matching runtime sidecars from
   `oc/runtime/ios/*.c` with the iPhoneOS clang.
3. Add all `.o` files to the app target's link step.
4. Provide a bridging header declaring its `<Entry>__init` and any
   `<Entry>__<Procedure>` it calls from Swift.

The iOS scheme in `oed/ios/` automates all four steps via a script
build phase.

## Status

Scaffold-grade. What works:

- `TerminalState` mutation via the full `ios_tui_*` shim surface.
- `TerminalView` renders rows of plain characters via `Text`.
- `Out.*` is routed through the same cell grid so basic
  hello-world programs print to a visible surface.

What's stubbed:

- `TerminalView` renders one `Text` per row — per-cell `fg` / `bg`
  / `attr` styling isn't applied yet. Replace with an `HStack` of
  per-cell `Text`s, or a `Canvas` draw, once oed drives the
  contents and needs the colour fidelity.
- Cursor rendering is unimplemented (`cursorVisible` is tracked but
  not painted).
- Keyboard input wiring — `oc_dispatch_key` is declared but no
  SwiftUI input handler invokes it yet. Hooking
  `View.onKeyPress` (iOS 17+) or a `UIKeyCommand` set is the
  next step.
- `Files` — `runtime/ios/Files.Mod`'s weak stubs return `NIL` /
  no-op. The iCloud ubiquity-container backend goes into a
  `FileShim.swift` here and a `Files_rt.c` in `runtime/ios/` when
  the storage layer lands.
