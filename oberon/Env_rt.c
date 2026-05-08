/* Env_rt.c — strong implementation backing Env.Mod.
 *
 * Calls into the OC runtime's argv stash, which is populated by the
 * compiler-emitted entry stub before any module init runs. */

#include <string.h>

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

void Env__init(void) {}
