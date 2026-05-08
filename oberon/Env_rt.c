/* Env_rt.c — strong implementation backing Env.Mod.
 *
 * Calls into the OC runtime's argv stash, which is populated by the
 * compiler-emitted entry stub before any module init runs. Cwd hits
 * libc directly. */

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

void Env__init(void) {}
