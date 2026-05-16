/* runtime/wasm/TUI_rt.c — wasm TUI runtime forwarding to JS imports.
 *
 * Each TUI operation is funnelled through one of the imported
 * functions below; the JS host (the "tui shim") binds them to a
 * terminal widget — xterm.js, a hand-rolled DOM <pre>, or whatever
 * the embedding chooses. The wasm module names every import under
 * the "tui" module so a single host can pick out all of them with
 * one entry in the WebAssembly.instantiate import object:
 *
 *     const wasm = await WebAssembly.instantiateStreaming(
 *         fetch("app.wasm"),
 *         { tui: { init, shutdown, write_char, write_str,
 *                  clear, clear_line, move_to, show_cursor,
 *                  hide_cursor, set_attr, flush, read_key,
 *                  rows, cols } } );
 *
 * String arguments cross as (ptr, len) into the wasm linear memory.
 * The JS shim must:
 *
 *     const view = new Uint8Array(wasm.instance.exports.memory.buffer);
 *     const s = new TextDecoder().decode(view.subarray(ptr, ptr + len));
 *
 * ReadKey is non-blocking — JS pushes keys into a queue on each
 * keydown event, the shim's read_key returns the next code or 0 if
 * the queue is empty. Real blocking input needs either
 * SharedArrayBuffer + Atomics.wait or the JS Promise Integration
 * proposal; for the prototype, callers poll. See tests/wasm/tui-shim.js
 * for a complete reference implementation. */

#include <stddef.h>
#include <stdint.h>

/* Wasm-side declarations of the JS-provided imports. The
 * import_module / import_name attributes make wasm-ld put these in
 * the "tui" namespace rather than the default "env". */
#define TUI_IMPORT(name) \
    __attribute__((import_module("tui"), import_name(#name)))

TUI_IMPORT(init)         extern void js_init(void);
TUI_IMPORT(shutdown)     extern void js_shutdown(void);
TUI_IMPORT(rows)         extern int  js_rows(void);
TUI_IMPORT(cols)         extern int  js_cols(void);
TUI_IMPORT(clear)        extern void js_clear(void);
TUI_IMPORT(clear_line)   extern void js_clear_line(void);
TUI_IMPORT(move_to)      extern void js_move_to(int col, int row);
TUI_IMPORT(show_cursor)  extern void js_show_cursor(void);
TUI_IMPORT(hide_cursor)  extern void js_hide_cursor(void);
TUI_IMPORT(set_attr)     extern void js_set_attr(int attr);
TUI_IMPORT(set_fg)       extern void js_set_fg(int color);
TUI_IMPORT(set_bg)       extern void js_set_bg(int color);
TUI_IMPORT(write_char)   extern void js_write_char(int ch);
TUI_IMPORT(write_str)    extern void js_write_str(const char *p, int n);
TUI_IMPORT(flush)        extern void js_flush(void);
TUI_IMPORT(read_key)     extern int  js_read_key(void);

/* Exported Oberon variables — declared in TUI.Mod, defined by the
 * compiler. The C runtime writes to them so the Oberon side sees
 * fresh dims after Init / Resize. */
extern int TUI__Rows;
extern int TUI__Cols;

static void refresh_dims(void) {
    TUI__Rows = js_rows();
    TUI__Cols = js_cols();
}

void TUI__Init(void) {
    js_init();
    refresh_dims();
}

void TUI__Shutdown(void) {
    js_shutdown();
}

void TUI__Resize(void) {
    refresh_dims();
}

void TUI__Clear(void) {
    js_clear();
}

void TUI__ClearLine(void) {
    js_clear_line();
}

void TUI__MoveTo(int col, int row) {
    js_move_to(col, row);
}

void TUI__ShowCursor(void) {
    js_show_cursor();
}

void TUI__HideCursor(void) {
    js_hide_cursor();
}

void TUI__SetAttr(int attr) {
    js_set_attr(attr);
}

void TUI__SetFg(int color) {
    js_set_fg(color);
}

void TUI__SetBg(int color) {
    js_set_bg(color);
}

void TUI__Write(char ch) {
    /* CHAR is i8 on the Oberon side. JS receives the byte value. */
    js_write_char((unsigned char)ch);
}

void TUI__WriteStr(const char *s, int n) {
    /* Oberon ABI for an open-array CHAR is (ptr, len). Pass through. */
    js_write_str(s, n);
}

/* itoa implemented locally — saves a JS round-trip just to format. */
static void write_uint(unsigned x) {
    char buf[12];
    int i = 0;
    if (x == 0) { js_write_char('0'); return; }
    while (x > 0 && i < (int)sizeof(buf)) {
        buf[i++] = (char)('0' + (x % 10));
        x /= 10;
    }
    while (i > 0) js_write_char((unsigned char)buf[--i]);
}

void TUI__WriteInt(int x) {
    if (x < 0) {
        js_write_char('-');
        write_uint((unsigned)(-(long)x));
    } else {
        write_uint((unsigned)x);
    }
}

void TUI__Flush(void) {
    js_flush();
}

int TUI__ReadKey(void) {
    js_flush();   /* match posix runtime — flush pending output before
                     polling input so partial frames are visible */
    return js_read_key();
}

/* Registered key handler. On wasm the program calls SetKeyHandler
 * then Run, and Run returns immediately. The JS host invokes the
 * exported `oc_dispatch_key` (below) on each keydown, which calls
 * the registered handler — flipping the polling model upside down
 * so the wasm thread never blocks waiting for JS. */
static void (*key_handler)(int) = NULL;

void TUI__SetKeyHandler(void (*h)(int)) {
    key_handler = h;
}

void TUI__Run(void) {
    /* No loop. JS dispatches keys via oc_dispatch_key while wasm
     * is suspended. */
}

void TUI__Quit(void) {
    key_handler = NULL;
    js_shutdown();
}

/* Exported for the JS shim to drive the handler from the browser's
 * keydown event. */
__attribute__((export_name("oc_dispatch_key")))
void oc_dispatch_key(int k) {
    if (key_handler) key_handler(k);
}

void TUI__init(void) {
    /* Don't auto-Init() here. The host program decides when to
     * switch the terminal into TUI mode. Matches the posix runtime. */
}
