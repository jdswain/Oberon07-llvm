/* runtime/wasm/Env_rt.c — Env backend for the browser host.
 *
 * argc / argv still flow through the runtime's argv stash (the
 * synthesised main() calls oc_set_args before any module init).
 * Cwd and BasePath defer to the JS shim — both are URL-derived,
 * read from window.location.pathname on the host side. The JS
 * writes the result into wasm memory at the pointer the wasm
 * passes in. */
#include <string.h>

extern int         oc_argc(void);
extern const char *oc_argv(int i);

#define ENV_IMPORT(name) \
    __attribute__((import_module("env"), import_name(#name)))

ENV_IMPORT(cwd)        extern void js_env_cwd      (char *out, int out_len);
ENV_IMPORT(base_path)  extern void js_env_base_path(char *out, int out_len);

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

void Env__Cwd(char *out, int out_len) {
    if (out_len <= 0) return;
    out[0] = 0;
    js_env_cwd(out, out_len);
}

void Env__BasePath(char *out, int out_len) {
    if (out_len <= 0) return;
    out[0] = 0;
    js_env_base_path(out, out_len);
}

void Env__init(void) {}
