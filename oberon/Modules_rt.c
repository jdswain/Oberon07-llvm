/* Modules_rt.c — C runtime backing oberon/Modules.Mod.
 *
 * Modules.Mod declares Module/ModDesc and stub bodies for Load/Free/
 * ThisCommand (weak linkage). This file provides strong overrides
 * that wrap dlopen / dlsym / dlclose.
 *
 * The dlopen handle for each loaded module is kept in a small in-process
 * side-table keyed by the ModDesc pointer. Keeping it out of the Oberon
 * record avoids needing 64-bit LONGINT-as-handle plumbing in the front
 * end and also keeps Module's layout simple.
 */
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Match the layout the compiler emits for Modules.ModDesc:
 *   { ptr tag, i64 _rc, [32 x i8] name, i32 refcnt, ptr next } */
typedef struct ModDesc {
    void           *_tag;
    int64_t         _rc;
    char            name[32];
    int             refcnt;
    struct ModDesc *next;
} ModDesc;

/* Side-table — one entry per live ModDesc. Linear search is fine for
 * the handful of modules a typical program loads. */
typedef struct HandleEntry {
    ModDesc            *m;
    void               *handle;
    struct HandleEntry *next;
} HandleEntry;

static HandleEntry *handles = NULL;

extern ModDesc *Modules__root;
extern ModDesc *Modules__NewModDesc(void);     /* defined by Modules.Mod */
extern void     oc_retain(void *p);
extern void     oc_release(void *p);

static void  remember_handle(ModDesc *m, void *h) {
    HandleEntry *e = (HandleEntry *)malloc(sizeof(HandleEntry));
    e->m = m; e->handle = h; e->next = handles;
    handles = e;
}

static void *lookup_handle(ModDesc *m) {
    for (HandleEntry *e = handles; e; e = e->next) {
        if (e->m == m) return e->handle;
    }
    return NULL;
}

static void forget_handle(ModDesc *m) {
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

/* Modules.Load(name, VAR newmod):
 *   if `name` is already loaded → bump refcnt, set newmod = existing
 *   else → dlopen("./<name>.dylib"), call <name>__init, link in list,
 *           set newmod = fresh ModDesc, refcnt = 1.
 *   On any failure → newmod = NIL.
 *
 * The Oberon ABI for `name: ARRAY OF CHAR` is (ptr, len) per our
 * open-array calling convention; we just take the ptr. `VAR newmod` is
 * a pointer-to-pointer; we manually run the ARC retain/release dance
 * since the C side bypasses the compiler's ORG_Store. */
void Modules__Load(const char *name, int name_len, ModDesc **newmod_addr) {
    (void)name_len;
    ModDesc *result = NULL;

    /* Search existing list. */
    for (ModDesc *m = Modules__root; m; m = m->next) {
        if (strneq32(m->name, name)) {
            m->refcnt++;
            result = m;
            break;
        }
    }

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
                /* link in front of list */
                m->next = Modules__root;
                if (m->next) oc_retain(m->next);
                if (Modules__root) oc_release(Modules__root);
                /* Take one strong reference for the root list. */
                oc_retain(m);
                Modules__root = m;
                remember_handle(m, h);

                /* Call the module's init function. */
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

    /* *newmod_addr := result, ARC dance. */
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
                /* unlink from list, drop our root-list reference */
                *prev = m->next;
                if (m->next) oc_retain(m->next);
                forget_handle(m);
                /* dlclose is intentionally skipped — keeping symbols
                 * resolvable for any stale references is safer than
                 * yanking them. */
                oc_release(m);
            }
            return;
        }
        prev = &(*prev)->next;
    }
}

/* Modules.ThisCommand(mod, name): dlsym for "<mod.name>__<name>".
 * Returns a function pointer (treated as Command). */
void *Modules__ThisCommand(ModDesc *m, const char *name, int name_len) {
    (void)name_len;
    if (!m) return NULL;
    void *h = lookup_handle(m);
    if (!h) return NULL;
    char sym[80];
    snprintf(sym, sizeof(sym), "%s__%s", m->name, name);
    return dlsym(h, sym);
}

/* Layout of one entry in `<mod>__exports`. The compiler emits this as
 * `{ ptr, ptr }`; we cast to ExportEntry on lookup. The array is
 * NULL-terminated (final entry has name == NULL). */
typedef struct ExportEntry {
    const char *name;
    void       *fn;
} ExportEntry;

static ExportEntry *load_exports(ModDesc *m) {
    if (!m) return NULL;
    void *h = lookup_handle(m);
    if (!h) return NULL;
    char sym[80];
    snprintf(sym, sizeof(sym), "%s__exports", m->name);
    return (ExportEntry *)dlsym(h, sym);
}

int Modules__ExportCount(ModDesc *m) {
    ExportEntry *t = load_exports(m);
    if (!t) return 0;
    int n = 0;
    while (t[n].name) n++;
    return n;
}

void Modules__ExportName(ModDesc *m, int idx,
                         char *out, int out_len) {
    if (out_len <= 0) return;
    out[0] = 0;
    ExportEntry *t = load_exports(m);
    if (!t) return;
    int n = 0;
    while (t[n].name) n++;
    if (idx < 0 || idx >= n) return;
    /* Copy the entry's name into the caller's buffer, zero-terminated. */
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
