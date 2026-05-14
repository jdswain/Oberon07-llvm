/* Tiny C runtime implementing Out.* — links against Oberon code that
   imports the Out.Mod stub. */
#include <stdio.h>

void Out__Write(char ch) {
    fputc((unsigned char)ch, stdout);
}

void Out__WriteString(const char *s, int n) {
    /* Oberon strings are 0X-terminated. Stop at NUL or n bytes, whichever first. */
    int i;
    for (i = 0; i < n && s[i] != 0; i++) fputc((unsigned char)s[i], stdout);
}

void Out__WriteInt(int x) {
    printf("%d", x);
}

void Out__Ln(void) {
    fputc('\n', stdout);
    fflush(stdout);
}

/* Out's own init is empty (the stub Out.Mod has no body). The compiler still
   emits a call to it from importers, so we must provide a definition. */
void Out__init(void) {}
