// swift-tools-version: 5.9
//
// OberonTUI — iOS host for Oberon programs compiled with oc -target
// arm64-apple-ios. Parallel to web/ (the browser host for the wasm
// target): provides a fixed-cell SwiftUI terminal and the @_cdecl
// shims (ios_tui_*, ios_out_*, ios_env_*) that the runtime/ios/
// sidecars forward to.
//
// Consuming app: add this package as a dependency, embed
// `TerminalView()` somewhere in the SwiftUI hierarchy, then compile
// your Oberon program with `oc -target arm64-apple-ios15.0` and link
// the resulting `.o` files into the app binary. See README.md for the
// full recipe.

import PackageDescription

let package = Package(
    name: "OberonTUI",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "OberonTUI",     targets: ["OberonTUI"]),
        .library(name: "OberonRuntime", targets: ["OberonRuntime"]),
    ],
    targets: [
        // Header-only C target exposing the runtime's C-ABI entry
        // points (oc_dispatch_key, oc_set_args) so Swift can call into
        // them. SPM requires at least one source file in a C target,
        // hence the placeholder empty.c.
        .target(
            name: "OberonRuntime",
            path: "Sources/OberonRuntime",
            publicHeadersPath: "include"
        ),
        .target(
            name: "OberonTUI",
            dependencies: ["OberonRuntime"],
            path: "Sources/OberonTUI"
        ),
    ]
)
