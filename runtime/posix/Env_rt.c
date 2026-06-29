/* Env_rt.c — strong implementation backing Env.Mod.
 *
 * Calls into the OC runtime's argv stash, which is populated by the
 * compiler-emitted entry stub before any module init runs. Cwd hits
 * libc directly. */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

extern int         oc_argc(void);
extern const char *oc_argv(int i);

int Env__ArgCount(void) {
    return oc_argc();
}

void Env__Arg(int i, char *out, int out_len) {
    if (out_len <= 0) return;
    out[0] = 0;
    const char *src = oc_argv(i);
    if (!src) return;
    size_t n = strlen(src);
    if (n > (size_t)(out_len - 1)) n = (size_t)(out_len - 1);
    memcpy(out, src, n);
    out[n] = 0;
}

/* Process working directory at call time. Truncates without error
 * if the buffer is too small; returns "" on getcwd failure. */
void Env__Cwd(char *out, int out_len) {
    if (out_len <= 0) return;
    out[0] = 0;
    if (!getcwd(out, (size_t)out_len)) {
        out[0] = 0;
    }
}

/* Project base path. POSIX has no notion of a URL-rooted project
 * tree, so we return the empty string. The wasm runtime fills this
 * in from window.location.pathname. */
void Env__BasePath(char *out, int out_len) {
    if (out_len > 0) out[0] = 0;
}

/* Open a URL via the host's default handler. Shells out to `open`
 * on macOS, `xdg-open` on Linux. The URL crosses as (ptr, len) per
 * the Oberon open-array ABI and isn't NUL-terminated, so we copy
 * into a fixed buffer before exec.
 *
 * Single-quoting the URL guards against shell metacharacters in
 * the URL itself; embedded single quotes still need escaping (we
 * just truncate at the first one — caller-supplied URLs are
 * trusted-ish, and we never write past the buffer). */
void Env__OpenURL(const char *url, int n) {
    if (!url || n <= 0) return;
    char buf[1024];
    if (n > (int)sizeof(buf) - 1) n = (int)sizeof(buf) - 1;
    memcpy(buf, url, (size_t)n);
    buf[n] = 0;
    /* Truncate at NUL or first single quote — see comment above. */
    for (int i = 0; i < n; i++) {
        if (buf[i] == 0 || buf[i] == '\'') { buf[i] = 0; break; }
    }
    char cmd[1100];
#if defined(__APPLE__)
    snprintf(cmd, sizeof(cmd), "open '%s' >/dev/null 2>&1 &", buf);
#else
    snprintf(cmd, sizeof(cmd), "xdg-open '%s' >/dev/null 2>&1 &", buf);
#endif
    int rc = system(cmd);
    (void)rc;
}

void Env__init(void) {}
