/* Modules_rt.c — C runtime backing oberon/Modules.Mod.
 *
 * Two loading modes are supported:
 *
 *   1. Static manifest. The driver-synthesised main.c emits
 *      `oc_module_manifest[]`, a NULL-terminated array of
 *      { name, init_fn, exports } records covering every module in
 *      the link closure. Modules.Load(name) searches this first.
 *      On wasm32 this is the only mode that works — there is no
 *      dlopen — and on native it lets short programs run without
 *      shipping .dylib files.
 *
 *   2. dlopen fallback. On native targets only, if the manifest
 *      doesn't have `name`, try dlopen("./<name>.dylib") and
 *      dlsym `<name>__init` / `<name>__exports`.
 *
 * Modules.Mod declares Module/ModDesc and stub bodies for Load /
 * Free / ThisCommand / ExportCount / ExportName / ExportProc /
 * LiveObjects with weak linkage. This file provides the strong
 * overrides; the per-ModDesc handle metadata lives in a small
 * in-process side-table.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#if !defined(__wasm32__) && !defined(__wasm__)
#  include <dlfcn.h>
#endif

/* Match the layout the compiler emits for Modules.ModDesc:
 *   { ptr tag, i64 _rc, [32 x i8] name, i32 refcnt, ptr next } */
typedef struct ModDesc {
    void           *_tag;
    int64_t         _rc;
    char            name[32];
    int             refcnt;
    struct ModDesc *next;
} ModDesc;

/* Static-link manifest emitted by oc_link's auto-generated main.c.
 * `weak` so binaries built with -shared (which don't have a main()
 * and therefore no manifest) still link cleanly. */
typedef struct {
    const char *name;
    void      (*init_fn)(void);
    void       *exports;
} OCModuleEntry;

__attribute__((weak))
extern const OCModuleEntry oc_module_manifest[];

/* Side-table — one entry per live ModDesc. Holds whichever loader
 * brought it in: a dlopen handle (native fallback) or a direct
 * pointer to the manifest's exports array (static mode). */
typedef struct HandleEntry {
    ModDesc            *m;
    void               *handle;      /* dlopen handle, NULL if manifest */
    void               *exports;     /* direct exports ptr, NULL if dlopen */
    struct HandleEntry *next;
} HandleEntry;

static HandleEntry *handles = NULL;

extern ModDesc *Modules__root;
extern ModDesc *Modules__NewModDesc(void);     /* defined by Modules.Mod */
extern void     oc_retain(void *p);
extern void     oc_release(void *p);

static void remember(ModDesc *m, void *handle, void *exports) {
    HandleEntry *e = (HandleEntry *)malloc(sizeof(HandleEntry));
    e->m = m; e->handle = handle; e->exports = exports; e->next = handles;
    handles = e;
}

static HandleEntry *lookup(ModDesc *m) {
    for (HandleEntry *e = handles; e; e = e->next) {
        if (e->m == m) return e;
    }
    return NULL;
}

static void forget(ModDesc *m) {
    HandleEntry **prev = &handles;
    while (*prev) {
        if ((*prev)->m == m) {
            HandleEntry *gone = *prev;
            *prev = gone->next;
            free(gone);
            return;
        }
        prev = &(*prev)->next;
    }
}

static int strneq32(const char *a, const char *b) {
    return strncmp(a, b, 32) == 0;
}

/* Locate `name` in the static manifest. Returns NULL if the manifest
 * symbol is absent (weak ref) or `name` isn't in it. */
static const OCModuleEntry *find_in_manifest(const char *name) {
    if (!oc_module_manifest) return NULL;
    for (const OCModuleEntry *e = oc_module_manifest; e->name; e++) {
        if (strncmp(e->name, name, 32) == 0) return e;
    }
    return NULL;
}

void Modules__Load(const char *name, int name_len, ModDesc **newmod_addr) {
    (void)name_len;
    ModDesc *result = NULL;

    /* Already loaded — bump refcount, return existing. */
    for (ModDesc *m = Modules__root; m; m = m->next) {
        if (strneq32(m->name, name)) {
            m->refcnt++;
            result = m;
            break;
        }
    }

    /* First lookup path: the compile-time manifest. Works on both
     * native and wasm, and is the only thing that works on wasm. */
    if (!result) {
        const OCModuleEntry *entry = find_in_manifest(name);
        if (entry) {
            ModDesc *m = Modules__NewModDesc();
            if (m) {
                strncpy(m->name, name, sizeof(m->name) - 1);
                m->name[sizeof(m->name) - 1] = 0;
                m->refcnt = 1;
                m->next = Modules__root;
                if (m->next) oc_retain(m->next);
                if (Modules__root) oc_release(Modules__root);
                oc_retain(m);
                Modules__root = m;
                remember(m, NULL, entry->exports);
                /* Module init is idempotent (compiler-emitted guard);
                 * the program's main() already ran it during start-up,
                 * but calling again is harmless and required for
                 * modules pulled in lazily by Load. */
                if (entry->init_fn) entry->init_fn();
                result = m;
            }
        }
    }

#if !defined(__wasm32__) && !defined(__wasm__)
    /* Fallback: dlopen "./<name>.dylib" — only on native targets. */
    if (!result) {
        char path[128];
        snprintf(path, sizeof(path), "./%s.dylib", name);
        void *h = dlopen(path, RTLD_NOW | RTLD_GLOBAL);
        if (!h) {
            fprintf(stderr, "Modules.Load: %s\n", dlerror());
        } else {
            ModDesc *m = Modules__NewModDesc();
            if (m) {
                strncpy(m->name, name, sizeof(m->name) - 1);
                m->name[sizeof(m->name) - 1] = 0;
                m->refcnt = 1;
                m->next = Modules__root;
                if (m->next) oc_retain(m->next);
                if (Modules__root) oc_release(Modules__root);
                oc_retain(m);
                Modules__root = m;
                remember(m, h, NULL);

                char sym[64];
                snprintf(sym, sizeof(sym), "%s__init", name);
                void (*init_fn)(void) = (void (*)(void))dlsym(h, sym);
                if (init_fn) init_fn();
                result = m;
            } else {
                dlclose(h);
            }
        }
    }
#endif

    if (result) oc_retain(result);
    if (*newmod_addr) oc_release(*newmod_addr);
    *newmod_addr = result;
}

void Modules__Free(const char *name, int name_len) {
    (void)name_len;
    ModDesc **prev = &Modules__root;
    while (*prev) {
        if (strneq32((*prev)->name, name)) {
            ModDesc *m = *prev;
            m->refcnt--;
            if (m->refcnt <= 0) {
                *prev = m->next;
                if (m->next) oc_retain(m->next);
                forget(m);
                /* dlclose is intentionally skipped — keeping symbols
                 * resolvable for any stale references is safer than
                 * yanking them. Manifest entries can't be unloaded
                 * at all. */
                oc_release(m);
            }
            return;
        }
        prev = &(*prev)->next;
    }
}

/* Modules.ThisCommand(mod, name): look up "<mod.name>__<name>".
 * Manifest path can't go through dlsym; instead walk the exports
 * table for a name match. dlopen path keeps the original dlsym route. */
void *Modules__ThisCommand(ModDesc *m, const char *name, int name_len) {
    (void)name_len;
    if (!m) return NULL;
    HandleEntry *e = lookup(m);
    if (!e) return NULL;

    if (e->exports) {
        /* exports is a pointer to a NULL-terminated array of
         * { const char *name, void *fn } pairs. */
        typedef struct { const char *name; void *fn; } ExportEntry;
        ExportEntry *t = (ExportEntry *)e->exports;
        for (int i = 0; t[i].name; i++) {
            if (strcmp(t[i].name, name) == 0) return t[i].fn;
        }
        return NULL;
    }

#if !defined(__wasm32__) && !defined(__wasm__)
    if (e->handle) {
        char sym[80];
        snprintf(sym, sizeof(sym), "%s__%s", m->name, name);
        return dlsym(e->handle, sym);
    }
#endif
    return NULL;
}

/* Exports-table introspection. Reads from the manifest's exports
 * pointer when available; otherwise falls back to dlsym lookup of
 * "<mod>__exports" for the dlopen-loaded case. */
typedef struct ExportEntry {
    const char *name;
    void       *fn;
} ExportEntry;

static ExportEntry *load_exports(ModDesc *m) {
    if (!m) return NULL;
    HandleEntry *e = lookup(m);
    if (!e) return NULL;
    if (e->exports) return (ExportEntry *)e->exports;
#if !defined(__wasm32__) && !defined(__wasm__)
    if (e->handle) {
        char sym[80];
        snprintf(sym, sizeof(sym), "%s__exports", m->name);
        return (ExportEntry *)dlsym(e->handle, sym);
    }
#endif
    return NULL;
}

int Modules__ExportCount(ModDesc *m) {
    ExportEntry *t = load_exports(m);
    if (!t) return 0;
    int n = 0;
    while (t[n].name) n++;
    return n;
}

void Modules__ExportName(ModDesc *m, int idx, char *out, int out_len) {
    if (out_len <= 0) return;
    out[0] = 0;
    ExportEntry *t = load_exports(m);
    if (!t) return;
    int n = 0;
    while (t[n].name) n++;
    if (idx < 0 || idx >= n) return;
    strncpy(out, t[idx].name, (size_t)out_len - 1);
    out[out_len - 1] = 0;
}

void *Modules__ExportProc(ModDesc *m, int idx) {
    ExportEntry *t = load_exports(m);
    if (!t) return NULL;
    int n = 0;
    while (t[n].name) n++;
    if (idx < 0 || idx >= n) return NULL;
    return t[idx].fn;
}

extern int64_t oc_live_objects(void);

int Modules__LiveObjects(void) {
    return (int)oc_live_objects();
}

void Modules__init(void) {}
