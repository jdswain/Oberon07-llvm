// OberonBridge — the single JVM-side surface the Oberon runtime
// C sidecars in runtime/android/*_rt.c call up to via JNI.
//
// C→Kotlin: the sidecars do FindClass("com/oneav/oberon/tui/OberonBridge")
//          then GetStaticMethodID for each `@JvmStatic` name. The
//          method signatures declared here (arg types + return type)
//          must match the JNI signatures in the C code:
//            tuiInit           ()V
//            tuiWriteChar      (I)V
//            tuiWriteStr       ([BI)V
//            envCwd            ()Ljava/lang/String;
//            envOpenUrl        (Ljava/lang/String;)V
//            ...
//
// Kotlin→C: `external fun` declarations map to
//          `Java_com_oneav_oberon_tui_OberonBridge_<name>` which are
//          exported from TUI_rt.c / runtime_android.c. Callers use
//          `System.loadLibrary("oed_oberon")` before touching these.
//
// All methods run on the UI thread — Kotlin never dispatches from a
// background thread, and Oberon's TUI ops are synchronous. If that
// ever changes we'll need to AttachCurrentThread from the C side
// (already handled in the get_env() helpers).

package com.oneav.oberon.tui

object OberonBridge {

    // ─── Kotlin → C ────────────────────────────────────────────

    /** Called by the Kotlin input handler for each keystroke.
     *  Invokes the Oberon-registered handler (TUI.SetKeyHandler). */
    external fun ocDispatchKey(code: Int)

    /** Prime the argv stash before any Oberon module init runs.
     *  Android apps have no meaningful argv — the C side just
     *  calls oc_set_args(0, NULL). */
    external fun ocSetArgs()

    /** POSIX chdir. Call once at Activity onCreate with a writable
     *  sandbox path (typically Context.filesDir) so the Oberon Files
     *  runtime resolves relative paths under it. */
    external fun ocChdir(path: String)

    // ─── C → Kotlin: TUI ──────────────────────────────────────

    @JvmStatic fun tuiInit()          { TerminalState.reset() }
    @JvmStatic fun tuiShutdown()      { /* view lifecycle owned by Compose */ }
    @JvmStatic fun tuiRows(): Int      = TerminalState.rows
    @JvmStatic fun tuiCols(): Int      = TerminalState.cols
    @JvmStatic fun tuiClear()         { TerminalState.clear() }
    @JvmStatic fun tuiClearLine()     { TerminalState.clearLine() }
    @JvmStatic fun tuiMoveTo(col: Int, row: Int) { TerminalState.moveTo(col, row) }
    @JvmStatic fun tuiShowCursor()    { TerminalState.setCursorVisible(true) }
    @JvmStatic fun tuiHideCursor()    { TerminalState.setCursorVisible(false) }
    @JvmStatic fun tuiSetAttr(a: Int) { TerminalState.setAttr(a) }
    @JvmStatic fun tuiSetFg(c: Int)   { TerminalState.setFg(c) }
    @JvmStatic fun tuiSetBg(c: Int)   { TerminalState.setBg(c) }
    @JvmStatic fun tuiWriteChar(ch: Int) {
        TerminalState.putChar(ch.toChar())
    }
    @JvmStatic fun tuiWriteStr(bytes: ByteArray, n: Int) {
        // Same NUL-terminated semantics as the iOS ios_tui_write_str:
        // stop at first 0 or `n`, whichever first. Also handle '\n'
        // as a row advance to match the wasm shim's behavior.
        val end = minOf(n, bytes.size)
        for (i in 0 until end) {
            val b = bytes[i].toInt() and 0xFF
            if (b == 0) return
            if (b == 0x0A) {
                TerminalState.moveTo(0, TerminalState.curRow + 1)
                continue
            }
            TerminalState.putChar(b.toChar())
        }
    }
    @JvmStatic fun tuiFlush()         { TerminalState.flush() }
    @JvmStatic fun tuiReadKey(): Int   = KeyQueue.pop() ?: 0

    // ─── C → Kotlin: Out ──────────────────────────────────────
    // Route Out.* into the same terminal grid — on-device Out has
    // no visible stdout. Mirrors the iOS OutShim behaviour.

    @JvmStatic fun outWriteChar(ch: Int) { tuiWriteChar(ch) }
    @JvmStatic fun outWriteStr(b: ByteArray, n: Int) { tuiWriteStr(b, n) }
    @JvmStatic fun outWriteInt(x: Int) {
        val s = x.toString()
        val bytes = s.toByteArray(Charsets.UTF_8)
        tuiWriteStr(bytes, bytes.size)
    }
    @JvmStatic fun outLn() {
        tuiWriteChar(0x0A)
        tuiFlush()
    }

    // ─── C → Kotlin: Env ──────────────────────────────────────

    @Volatile var cwd: String = ""
    @Volatile var basePath: String = ""

    /** Set by the Activity via `EnvBridge.setActivity(this)` before
     *  Oed__init runs; used by envOpenUrl to fire an Intent. */
    @Volatile var openUrl: (String) -> Unit = { }

    @JvmStatic fun envCwd(): String      = cwd
    @JvmStatic fun envBasePath(): String = basePath
    @JvmStatic fun envOpenUrl(url: String) { openUrl(url) }
}
