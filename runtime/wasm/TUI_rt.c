/* runtime/wasm/TUI_rt.c — placeholder Terminal-UI runtime for wasm.
 *
 * The posix variant drives a real PTY via termios + ANSI escape
 * sequences (see runtime/posix/TUI_rt.c). Wasm has no PTY, and WASI
 * 0.1 doesn't have a portable tty story. For now this is a pure
 * stub: every output is dropped, ReadKey blocks would be the wrong
 * semantics so it just returns 0. Rows / Cols are initialised to a
 * reasonable default in case anyone reads them before Init.
 *
 * The long-term browser implementation forwards each call to a JS
 * shim: TUI__Write becomes a postMessage into a terminal widget,
 * TUI__ReadKey returns a code pushed in from a keyboard event,
 * Rows/Cols come from the JS-side resize observer. */
#include <stdint.h>

int TUI__Rows = 24;
int TUI__Cols = 80;

void TUI__Init(void)        {}
void TUI__Shutdown(void)    {}
void TUI__Resize(void)      {}
void TUI__Clear(void)       {}
void TUI__ClearLine(void)   {}
void TUI__MoveTo(int col, int row)  { (void)col; (void)row; }
void TUI__ShowCursor(void)  {}
void TUI__HideCursor(void)  {}
void TUI__SetAttr(int a)    { (void)a; }
void TUI__Write(char ch)    { (void)ch; }
void TUI__WriteStr(const char *s, int n) { (void)s; (void)n; }
void TUI__WriteInt(int x)   { (void)x; }
void TUI__Flush(void)       {}
int  TUI__ReadKey(void)     { return 0; }

void TUI__init(void) {}
