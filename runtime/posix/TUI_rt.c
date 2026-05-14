/* TUI_rt.c — strong implementation backing TUI.Mod.
 *
 * Raw-mode terminal I/O: ANSI escape emission, buffered output, key
 * decoding from CSI sequences. The Oberon stubs in TUI.Mod link as
 * weak symbols; these definitions override them.
 *
 * The Oberon-side exported variables Rows and Cols are name-mangled
 * to TUI__Rows / TUI__Cols by the compiler; we touch them directly
 * from C so callers see fresh values after Init / Resize.
 */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>

#define KEY_NONE        (-1)
#define KEY_ARROW_UP    256
#define KEY_ARROW_DOWN  257
#define KEY_ARROW_LEFT  258
#define KEY_ARROW_RIGHT 259
#define KEY_HOME        260
#define KEY_END         261
#define KEY_PAGE_UP     262
#define KEY_PAGE_DOWN   263
#define KEY_DELETE      264

/* Meta keys (ESC followed by a single ASCII char within ~100ms). */
#define KEY_META_LT     290
#define KEY_META_GT     291
#define KEY_META_F      292
#define KEY_META_B      293
#define KEY_META_A      294
#define KEY_META_E      295
#define KEY_META_W      296
#define KEY_META_Y      297
#define KEY_META_N      298
#define KEY_META_P      299

extern int TUI__Rows;
extern int TUI__Cols;

static struct termios saved_termios;
static int            raw_active = 0;

#define OUTBUF_SIZE 16384
static char outbuf[OUTBUF_SIZE];
static int  outlen = 0;

static void write_all(const void *p, int n) {
    const char *s = (const char *)p;
    while (n > 0) {
        ssize_t w = write(STDOUT_FILENO, s, (size_t)n);
        if (w < 0) {
            if (errno == EINTR) continue;
            return;
        }
        s += w; n -= (int)w;
    }
}

static void out_flush(void) {
    if (outlen > 0) { write_all(outbuf, outlen); outlen = 0; }
}

static void out_emit(const char *s, int n) {
    if (n <= 0) return;
    if (n >= OUTBUF_SIZE) { out_flush(); write_all(s, n); return; }
    if (outlen + n > OUTBUF_SIZE) out_flush();
    memcpy(outbuf + outlen, s, (size_t)n);
    outlen += n;
}

static void out_str(const char *s) { out_emit(s, (int)strlen(s)); }

static void restore_terminal(void) {
    if (!raw_active) return;
    out_flush();
    write_all("\x1b[0m",   4);  /* reset attributes */
    write_all("\x1b[?25h", 6);  /* show cursor      */
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &saved_termios);
    raw_active = 0;
}

void TUI__Resize(void) {
    struct winsize ws;
    if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0 && ws.ws_col > 0) {
        TUI__Cols = ws.ws_col;
        TUI__Rows = ws.ws_row;
    } else {
        TUI__Cols = 80;
        TUI__Rows = 24;
    }
}

void TUI__Init(void) {
    if (raw_active) { TUI__Resize(); return; }
    if (tcgetattr(STDIN_FILENO, &saved_termios) == -1) {
        perror("TUI.Init: tcgetattr");
        exit(1);
    }
    struct termios raw = saved_termios;
    raw.c_iflag &= ~(BRKINT | ICRNL | INPCK | ISTRIP | IXON);
    raw.c_oflag &= ~(OPOST);
    raw.c_cflag |=  (CS8);
    raw.c_lflag &= ~(ECHO | ICANON | IEXTEN | ISIG);
    raw.c_cc[VMIN]  = 1;
    raw.c_cc[VTIME] = 0;
    if (tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == -1) {
        perror("TUI.Init: tcsetattr");
        exit(1);
    }
    raw_active = 1;
    atexit(restore_terminal);
    TUI__Resize();
}

void TUI__Shutdown(void) {
    restore_terminal();
}

void TUI__Clear(void) {
    out_str("\x1b[2J");
    out_str("\x1b[H");
}

void TUI__ClearLine(void) {
    out_str("\x1b[K");
}

void TUI__MoveTo(int col, int row) {
    /* Oberon callers count from 0; ANSI counts from 1. */
    char buf[32];
    int n = snprintf(buf, sizeof(buf), "\x1b[%d;%dH", row + 1, col + 1);
    if (n > 0) out_emit(buf, n);
}

void TUI__ShowCursor(void) { out_str("\x1b[?25h"); }
void TUI__HideCursor(void) { out_str("\x1b[?25l"); }

void TUI__SetAttr(int attr) {
    out_str("\x1b[0m");
    if (attr & 1) out_str("\x1b[7m");
    if (attr & 2) out_str("\x1b[1m");
}

void TUI__Write(char ch) { out_emit(&ch, 1); }

void TUI__WriteStr(const char *s, int n) {
    int i = 0;
    while (i < n && s[i] != 0) i++;
    out_emit(s, i);
}

void TUI__WriteInt(int x) {
    char buf[32];
    int n = snprintf(buf, sizeof(buf), "%d", x);
    if (n > 0) out_emit(buf, n);
}

void TUI__Flush(void) { out_flush(); }

/* Read one byte. blocking=1 honours raw-mode VMIN=1; blocking=0 swaps
 * to VMIN=0 / VTIME=1 (100 ms) so escape-sequence followups time out
 * cleanly when the user pressed a bare ESC. */
static int read_one(unsigned char *c, int blocking) {
    if (!blocking) {
        struct termios cur, t;
        if (tcgetattr(STDIN_FILENO, &cur) == -1) return 0;
        t = cur;
        t.c_cc[VMIN]  = 0;
        t.c_cc[VTIME] = 1;
        tcsetattr(STDIN_FILENO, TCSANOW, &t);
        ssize_t r = read(STDIN_FILENO, c, 1);
        tcsetattr(STDIN_FILENO, TCSANOW, &cur);
        return r == 1;
    }
    for (;;) {
        ssize_t r = read(STDIN_FILENO, c, 1);
        if (r == 1) return 1;
        if (r == -1 && (errno == EAGAIN || errno == EINTR)) continue;
        return 0;
    }
}

int TUI__ReadKey(void) {
    out_flush();

    unsigned char c;
    if (!read_one(&c, 1)) return KEY_NONE;
    if (c != 0x1b) return c;

    unsigned char a;
    if (!read_one(&a, 0)) return 0x1b;     /* lone ESC */

    /* If the followup isn't a CSI/SS3 introducer, treat the sequence
     * as Meta-X. Unrecognized Meta-X falls back to bare Esc. */
    if (a != '[' && a != 'O') {
        switch (a) {
        case '<': return KEY_META_LT;
        case '>': return KEY_META_GT;
        case 'f': return KEY_META_F;
        case 'b': return KEY_META_B;
        case 'a': return KEY_META_A;
        case 'e': return KEY_META_E;
        case 'w': return KEY_META_W;
        case 'y': return KEY_META_Y;
        case 'n': return KEY_META_N;
        case 'p': return KEY_META_P;
        }
        return 0x1b;
    }

    /* CSI ('[') or SS3 ('O') sequence — needs a second followup. */
    unsigned char b;
    if (!read_one(&b, 0)) return 0x1b;

    if (a == '[') {
        unsigned char d;
        if (b >= '0' && b <= '9') {
            if (read_one(&d, 0) && d == '~') {
                switch (b) {
                case '1': case '7': return KEY_HOME;
                case '4': case '8': return KEY_END;
                case '3':           return KEY_DELETE;
                case '5':           return KEY_PAGE_UP;
                case '6':           return KEY_PAGE_DOWN;
                }
            }
        } else {
            switch (b) {
            case 'A': return KEY_ARROW_UP;
            case 'B': return KEY_ARROW_DOWN;
            case 'C': return KEY_ARROW_RIGHT;
            case 'D': return KEY_ARROW_LEFT;
            case 'H': return KEY_HOME;
            case 'F': return KEY_END;
            }
        }
    } else if (a == 'O') {
        switch (b) {
        case 'H': return KEY_HOME;
        case 'F': return KEY_END;
        }
    }
    return 0x1b;
}

void TUI__init(void) {
    /* Module body is empty; callers invoke TUI.Init explicitly. */
}
