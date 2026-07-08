# Android runtime

Runtime modules for the `aarch64-linux-android*` target. Same shape
as `runtime/ios/`: `.Mod` files give Oberon importers a typed
signature with empty (weak-linkage) bodies, and `_rt.c` sidecars
override those bodies. On Android the sidecars do JNI upcalls into
Kotlin methods on a single bridge class.

## Selecting this runtime

The compiler picks it via the `-target` triple. Anything containing
`-android` routes here:

    bin/oc -target aarch64-linux-android24 Tiny.Mod      # ARMv8 device / emulator
    bin/oc -target x86_64-linux-android24 Tiny.Mod       # x86_64 emulator

Use a versioned suffix (`android24` = Android 7 Nougat baseline) so
the Mach-O–equivalent ELF gets its minimum SDK stamped in.

The `oc` driver does **not** link Android binaries. Compile each
Oberon module to a `.o`, then link them together with the C
sidecars + Kotlin native library from a Gradle build in the app
(`oed/android/`).

## Host bridge contract

Every C sidecar calls up to a single Kotlin `object`:

    package com.oneav.oberon.tui
    object OberonBridge {
        // TUI surface
        @JvmStatic fun tuiInit()
        @JvmStatic fun tuiShutdown()
        @JvmStatic fun tuiRows(): Int
        @JvmStatic fun tuiCols(): Int
        @JvmStatic fun tuiClear()
        @JvmStatic fun tuiClearLine()
        @JvmStatic fun tuiMoveTo(col: Int, row: Int)
        @JvmStatic fun tuiShowCursor()
        @JvmStatic fun tuiHideCursor()
        @JvmStatic fun tuiSetAttr(attr: Int)
        @JvmStatic fun tuiSetFg(color: Int)
        @JvmStatic fun tuiSetBg(color: Int)
        @JvmStatic fun tuiWriteChar(ch: Int)
        @JvmStatic fun tuiWriteStr(bytes: ByteArray, n: Int)
        @JvmStatic fun tuiFlush()
        @JvmStatic fun tuiReadKey(): Int

        // Out surface — same target as TUI on-device
        @JvmStatic fun outWriteChar(ch: Int)
        @JvmStatic fun outWriteStr(bytes: ByteArray, n: Int)
        @JvmStatic fun outWriteInt(x: Int)
        @JvmStatic fun outLn()

        // Env surface
        @JvmStatic fun envCwd(): String
        @JvmStatic fun envBasePath(): String
        @JvmStatic fun envOpenUrl(url: String)

        // Reverse direction — Kotlin calls these
        external fun ocDispatchKey(code: Int)
        external fun ocSetArgs()
    }

The `oc/android/` SPM-equivalent Gradle module implements this in
Kotlin against a Jetpack Compose terminal view.

## Files

`Files_rt.c` is copied verbatim from `runtime/posix/`. Android's
bionic libc provides POSIX file I/O within the app's private
storage directory, so no JNI plumbing needed on that side; the
Kotlin bootstrap `chdir()`'s into `Context.filesDir` at startup.

## What's stubbed

- `Env.ArgCount` returns 0.
- `Files` behind the POSIX runtime uses whatever directory the
  Kotlin side `chdir`'d to. `Context.filesDir` (private) is the
  default; `Context.getExternalFilesDir(null)` is where you'd
  swap in for user-visible SAF-mediated files later.
