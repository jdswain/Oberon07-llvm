/* runtime/wasm/FileDir_rt.c — placeholder directory operations for
 * the wasm runtime. Mirrors runtime/wasm/Files_rt.c: returns the
 * "nothing here" answer to each query rather than failing.
 *
 * Future WASI impl can reuse runtime/posix/FileDir_rt.c almost
 * verbatim (opendir / readdir / unlink are WASI-supported). The
 * browser version will proxy to JS / a backend service. */
#include <stdint.h>

void FileDir__Search(const char *name, int *A) {
    (void)name;
    if (A) *A = 0;
}

void FileDir__Insert(const char *name, int fad) {
    (void)name; (void)fad;
}

void FileDir__Delete(const char *name, int *fad) {
    (void)name;
    if (fad) *fad = 0;
}

/* EntryHandler is (name_ptr, sec, *cont) per the Oberon ABI. */
typedef void (*EntryHandler)(const char *name_ptr, int sec, int8_t *cont);

void FileDir__Enumerate(const char *prefix, int prefix_len, EntryHandler proc) {
    (void)prefix; (void)prefix_len; (void)proc;
}

void FileDir__Init(void) {}
void FileDir__init(void) {}
