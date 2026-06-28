/* runtime/ios/Out_rt.c — Out backend forwarding to the Swift host.
 *
 * The Swift app exports four @_cdecl functions matching the externs
 * below; the linker resolves them at app-build time. Output is
 * typically routed to the on-screen TUI (so Out.WriteString and
 * TUI.Write share the same destination) but the host is free to
 * also surface it to a debug log. */

extern void ios_out_write     (int ch);
extern void ios_out_writestr  (const char *s, int n);
extern void ios_out_writeint  (int x);
extern void ios_out_ln        (void);

void Out__Write(char ch) {
    ios_out_write((unsigned char)ch);
}

void Out__WriteString(const char *s, int n) {
    ios_out_writestr(s, n);
}

void Out__WriteInt(int x) {
    ios_out_writeint(x);
}

void Out__Ln(void) {
    ios_out_ln();
}

void Out__init(void) {}
