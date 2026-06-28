/* runtime/ios/TUI_rt.c — iOS TUI runtime forwarding to Swift externs.
 *
 * The contract mirrors runtime/wasm/TUI_rt.c exactly so a port from
 * the web port to the iOS app is mechanical:
 *
 *   - The Swift app exports @_cdecl C-ABI functions with the
 *     `ios_tui_*` names below; the linker resolves them at app-build
 *     time.
 *   - The host implementation backs them with a SwiftUI cell-grid
 *     view (analogous to the DOM <div> grid the wasm tui-shim builds).
 *
 * ReadKey is non-blocking — Swift pushes key codes into a queue on
 * each keyboard event, the host's ios_tui_read_key returns the next
 * code or 0 if the queue is empty. The event-driven path
 * (SetKeyHandler / Run) is preferred on iOS: the UI thread can't
 * spin waiting for input. */

#include <stddef.h>
#include <stdint.h>

extern void ios_tui_init        (void);
extern void ios_tui_shutdown    (void);
extern int  ios_tui_rows        (void);
extern int  ios_tui_cols        (void);
extern void ios_tui_clear       (void);
extern void ios_tui_clear_line  (void);
extern void ios_tui_move_to     (int col, int row);
extern void ios_tui_show_cursor (void);
extern void ios_tui_hide_cursor (void);
extern void ios_tui_set_attr    (int attr);
extern void ios_tui_set_fg      (int color);
extern void ios_tui_set_bg      (int color);
extern void ios_tui_write_char  (int ch);
extern void ios_tui_write_str   (const char *p, int n);
extern void ios_tui_flush       (void);
extern int  ios_tui_read_key    (void);

/* Exported Oberon variables — declared in TUI.Mod, defined by the
 * compiler. The C runtime writes to them so the Oberon side sees
 * fresh dims after Init / Resize. */
extern int TUI__Rows;
extern int TUI__Cols;

static void refresh_dims(void) {
    TUI__Rows = ios_tui_rows();
    TUI__Cols = ios_tui_cols();
}

void TUI__Init(void) {
    ios_tui_init();
    refresh_dims();
}

void TUI__Shutdown(void) {
    ios_tui_shutdown();
}

void TUI__Resize(void) {
    refresh_dims();
}

void TUI__Clear(void) {
    ios_tui_clear();
}

void TUI__ClearLine(void) {
    ios_tui_clear_line();
}

void TUI__MoveTo(int col, int row) {
    ios_tui_move_to(col, row);
}

void TUI__ShowCursor(void) {
    ios_tui_show_cursor();
}

void TUI__HideCursor(void) {
    ios_tui_hide_cursor();
}

void TUI__SetAttr(int attr) {
    ios_tui_set_attr(attr);
}

void TUI__SetFg(int color) {
    ios_tui_set_fg(color);
}

void TUI__SetBg(int color) {
    ios_tui_set_bg(color);
}

void TUI__Write(char ch) {
    /* CHAR is i8 on the Oberon side. Swift receives the byte value. */
    ios_tui_write_char((unsigned char)ch);
}

void TUI__WriteStr(const char *s, int n) {
    /* Oberon ABI for an open-array CHAR is (ptr, len). Pass through. */
    ios_tui_write_str(s, n);
}

/* itoa implemented locally — saves a Swift round-trip just to format. */
static void write_uint(unsigned x) {
    char buf[12];
    int i = 0;
    if (x == 0) { ios_tui_write_char('0'); return; }
    while (x > 0 && i < (int)sizeof(buf)) {
        buf[i++] = (char)('0' + (x % 10));
        x /= 10;
    }
    while (i > 0) ios_tui_write_char((unsigned char)buf[--i]);
}

void TUI__WriteInt(int x) {
    if (x < 0) {
        ios_tui_write_char('-');
        write_uint((unsigned)(-(long)x));
    } else {
        write_uint((unsigned)x);
    }
}

void TUI__Flush(void) {
    ios_tui_flush();
}

int TUI__ReadKey(void) {
    ios_tui_flush();   /* match posix / wasm — flush pending output before
                          polling input so partial frames are visible */
    return ios_tui_read_key();
}

/* Registered key handler. The Swift host calls oc_dispatch_key (below)
 * on each keyboard event, which invokes the registered handler — flipping
 * the polling model upside down so the main thread never blocks waiting
 * for input. */
static void (*key_handler)(int) = NULL;

void TUI__SetKeyHandler(void (*h)(int)) {
    key_handler = h;
}

void TUI__Run(void) {
    /* No loop. Swift dispatches keys via oc_dispatch_key while the
     * Oberon code is suspended waiting for the next event. */
}

void TUI__Quit(void) {
    key_handler = NULL;
    ios_tui_shutdown();
}

/* Exported for the Swift host to drive the handler from keyboard events. */
void oc_dispatch_key(int k) {
    if (key_handler) key_handler(k);
}

void TUI__init(void) {
    /* Don't auto-Init() here. The host program decides when to switch
     * the terminal into TUI mode. Matches the posix runtime. */
}
