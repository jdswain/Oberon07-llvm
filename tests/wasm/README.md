# WASM prototype

End-to-end smoke test of the wasm32 backend.

```
$ oc -target wasm32 -o hello.wasm WasmHello.Mod
$ wasmtime hello.wasm
hello from oberon-wasm
1+2+...+10 = 55
```

## What's here

- `WasmHello.Mod` — single Oberon module, imports `Out`, prints a
  greeting and a small loop result. Exercises the basics: module init,
  `Out.WriteString`, `Out.WriteInt`, `Out.Ln`, a `FOR` loop, integer
  arithmetic.

## How the build differs from native

- `oc -target wasm32` sets the LLVM target triple to `wasm32-wasip1`
  before code emission, so every `.o` produced is a WebAssembly object
  rather than Mach-O.
- `oc_link` detects the wasm target and invokes Homebrew's clang
  (override with `OC_WASM_CLANG`) with `--target=wasm32-wasip1`,
  `--sysroot=$(brew --prefix wasi-libc)/share/wasi-sysroot`,
  `-resource-dir=$(brew --prefix wasi-runtimes)/share/wasi-runtimes`.
  The linker is clang's bundled `wasm-ld`.
- `needs_compile` checks each `.o`'s first four bytes for the wasm
  `\0asm` magic and forces a rebuild when the target switches, so
  flipping between native and wasm builds Just Works.

## Limitations of the prototype

- `Modules.Load` / `Free` / `ThisCommand` are still stubs on wasm —
  `dlopen` has no wasm equivalent. The test framework's dynamic
  plugin model won't run here. A statically-linked test harness
  would need a registration table generated at compile time.
- `SYSTEM.ADR` returns `LONGINT` (i64) regardless of target. On
  wasm32 the actual pointer width is 32 bits, so addresses get
  zero-extended into the i64. Round-trips through `SYSTEM.GET/PUT/COPY`
  still work because we `inttoptr` back, but the high half is junk
  that callers must not look at.
- No threads, no WASI directory iteration (`FileDir.Enumerate` won't
  list anything useful), no GUI / display.

## Toolchain prerequisites

```
brew install wasmtime lld wasi-libc wasi-runtimes
```

(LLVM with the WebAssembly target — Homebrew's `llvm` already has it.)
