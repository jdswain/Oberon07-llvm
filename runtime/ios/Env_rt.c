/* runtime/ios/Env_rt.c — Env backend for the iOS host.
 *
 * iOS apps don't have a meaningful argv: launches come from springboard
 * with no arguments. ArgCount returns 0, Arg returns an empty string.
 * Cwd is the app's sandboxed working directory (the Documents directory
 * is the usual choice); BasePath is the project root within whichever
 * filestore the host points at (initially the app's iCloud ubiquity
 * container — see Files_rt.c). Both are filled by the Swift side. */
#include <stddef.h>

extern void ios_env_cwd       (char *out, int out_len);
extern void ios_env_base_path (char *out, int out_len);

int Env__ArgCount(void) {
    return 0;
}

void Env__Arg(int i, char *out, int out_len) {
    (void)i;
    if (out_len > 0) out[0] = 0;
}

void Env__Cwd(char *out, int out_len) {
    if (out_len <= 0) return;
    out[0] = 0;
    ios_env_cwd(out, out_len);
}

void Env__BasePath(char *out, int out_len) {
    if (out_len <= 0) return;
    out[0] = 0;
    ios_env_base_path(out, out_len);
}

void Env__init(void) {}
