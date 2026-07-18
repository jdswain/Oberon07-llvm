/*
 * main.c — driver for the self-hosted Oberon compiler (oc-self).
 * GENERATED from the driver section of src/ORP.c by gen_bridge.py.
 *
 * Arg parsing, recursive compilation of stale imports, and linking stay
 * in C (they are host-OS plumbing: getpid, system, clang invocations).
 * The compiler proper is the Oberon modules ORS/ORB/ORP + the C LLVM
 * backend ORG_rt.c.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include <unistd.h>
#include <ctype.h>
#include <sys/stat.h>

typedef int32_t INTEGER;
typedef int64_t LONGINT;
typedef bool    BOOLEAN;
#define TRUE  true
#define FALSE false

/* Oberon entry points (mangled names) */
extern void ORP__init(void);                       /* module init chain  */
extern void ORP__Compile(const char *name, INTEGER len, BOOLEAN force);
extern INTEGER ORS__errcnt;
extern void ORB__AddSearchPath(const char *path, INTEGER len);

/* C-side backend configuration (ORG_rt.c) */
extern void ORG_SetEmitFlags(BOOLEAN emit_ll, BOOLEAN emit_obj);
extern void ORG_SetTargetTriple(const char *triple);
extern void ORG_SetSourceDir(const char *dir);

static void AddSearchPath(const char *path) {
    /* The Oberon module bodies zero ORB's search-path table; they are
     * guarded (run-once), so force the init chain BEFORE registering
     * paths or they'd be wiped when the compile entry runs the chain. */
    ORP__init();
    ORB__AddSearchPath(path, (INTEGER)strlen(path) + 1);
}

/* Source directory, shared with the C backend for .ll/.o/.deps paths and
 * consulted by the linker for .deps lookups. */
static char main_source_dir[512];
static const char *GetSourceDir(void) { return main_source_dir; }

/* ============ generated from src/ORP.c driver section below ============ */

// Resolved at startup: directory containing the runtime modules (Out.Mod,
// Modules.Mod, runtime.c, etc.). Auto-compile and the linker look here as
// a fallback when a module isn't in the user's source directory.
static char RuntimeDir[1024] = "";

/* Pick the runtime modules subdirectory based on the active target.
 * wasm32 → runtime/wasm/, everything else → runtime/posix/. Both live
 * next to or one level above the compiler binary so the same lookup
 * works from `bin/oc` (../runtime) or a flat install (./runtime). */
/* Map a target triple to a runtime flavour subdirectory under runtime/.
 * `-ios` matches both arm64-apple-ios and arm64-apple-ios-simulator (and
 * the versioned forms like arm64-apple-ios15.0); device and simulator
 * share runtime sources because the only differences are linker config
 * and the SDK, both handled outside the compiler. */
static const char *runtime_flavor(const char *target) {
    if (!target)                       return "posix";
    if (strstr(target, "wasm"))        return "wasm";
    if (strstr(target, "-ios"))        return "ios";
    if (strstr(target, "-android"))    return "android";
    return "posix";
}

static void resolve_runtime_dir(const char *self_argv0, const char *target) {
    char self_abs[1024];
    if (realpath(self_argv0, self_abs) == NULL) return;
    char *last_slash = strrchr(self_abs, '/');
    if (!last_slash) return;
    *last_slash = 0;
    const char *flavor = runtime_flavor(target);
    /* Layouts to probe, in order. */
    char tryp[1024];
    const char *layouts[] = {
        "/../runtime/%s/", "/runtime/%s/",
        /* Backwards compat with the pre-split layout. */
        "/../oberon/",     "/oberon/",
        NULL,
    };
    for (int i = 0; layouts[i]; i++) {
        if (strstr(layouts[i], "%s")) {
            snprintf(tryp, sizeof(tryp), layouts[i], flavor);
        } else {
            snprintf(tryp, sizeof(tryp), "%s", layouts[i]);
        }
        snprintf(RuntimeDir, sizeof(RuntimeDir), "%s%s", self_abs, tryp);
        if (access(RuntimeDir, R_OK) == 0) return;
    }
    RuntimeDir[0] = 0;
}

// Find a runtime .c file relative to the running compiler binary.
// Used for runtime.c (always included), Modules_rt.c (included when
// the transitive import graph mentions the Modules module), etc. Uses
// the same target-aware layout search as resolve_runtime_dir.
static int find_runtime_file(const char *self_argv0, const char *basename,
                             const char *target,
                             char *out, size_t outsz) {
    char self_abs[1024];
    if (realpath(self_argv0, self_abs) == NULL) return -1;
    char *last_slash = strrchr(self_abs, '/');
    if (!last_slash) return -1;
    *last_slash = 0;
    const char *flavor = runtime_flavor(target);
    char tryp[1024];
    const char *layouts[] = {
        "/../runtime/%s/", "/runtime/%s/",
        "/../oberon/",     "/oberon/",     "/",
        NULL,
    };
    for (int i = 0; layouts[i]; i++) {
        if (strstr(layouts[i], "%s")) {
            snprintf(tryp, sizeof(tryp), layouts[i], flavor);
        } else {
            snprintf(tryp, sizeof(tryp), "%s", layouts[i]);
        }
        snprintf(out, outsz, "%s%s%s", self_abs, tryp, basename);
        if (access(out, R_OK) == 0) return 0;
    }
    return -1;
}

static int find_runtime_source(const char *self_argv0, const char *target,
                               char *out, size_t outsz) {
    return find_runtime_file(self_argv0, "runtime.c", target, out, outsz);
}

// Auto-link helper: walks the transitive .deps closure rooted at entry,
// generates a tiny C main() that calls <entry>__init(), and shells out to
// clang to produce a native binary linking entry.ll, all transitive .ll
// files, and any user-supplied extras (.c / .o / -lfoo / etc).
#define MAX_LINK_MODS 256
#define MAX_LINK_NAME 64

static BOOLEAN list_has(char names[][MAX_LINK_NAME], int n, const char *s) {
    for (int i = 0; i < n; i++) if (strcmp(names[i], s) == 0) return TRUE;
    return FALSE;
}

// --- Recursive auto-compile: invoked by `oc -o prog Main.Mod` so the user
// only has to keep the `.Mod` files up to date; the driver compiles each
// transitive import that's missing or older than its source.

// Locate a module's .Mod source. Tries the user's source dir first, then
// the runtime dir (oberon/ next to the compiler binary). Returns 0 on
// success, -1 if neither path exists.
static int locate_module_source(const char *source_dir, const char *modname,
                                char *out, size_t outsz) {
    snprintf(out, outsz, "%s%s.Mod", source_dir, modname);
    if (access(out, R_OK) == 0) return 0;
    if (RuntimeDir[0]) {
        snprintf(out, outsz, "%s%s.Mod", RuntimeDir, modname);
        if (access(out, R_OK) == 0) return 0;
    }
    return -1;
}

// Same idea for a module's .o (used by the linker).
static int locate_module_object(const char *source_dir, const char *modname,
                                char *out, size_t outsz) {
    snprintf(out, outsz, "%s%s.o", source_dir, modname);
    if (access(out, R_OK) == 0) return 0;
    if (RuntimeDir[0]) {
        snprintf(out, outsz, "%s%s.o", RuntimeDir, modname);
        if (access(out, R_OK) == 0) return 0;
    }
    return -1;
}

// Quick textual scanner for `IMPORT a, b := c, d;` clauses. Strips nested
// (* *) comments first. Reads up to 16 KB of the source which is more
// than enough to reach the IMPORT clause at the top of the module.
static int scan_imports(const char *source_dir, const char *modname,
                        char out[][MAX_LINK_NAME], int max) {
    char path[512];
    if (locate_module_source(source_dir, modname, path, sizeof(path)) != 0) {
        return 0;
    }
    FILE *f = fopen(path, "r");
    if (!f) return 0;
    char buf[16384];
    size_t n = fread(buf, 1, sizeof(buf) - 1, f);
    buf[n] = 0;
    fclose(f);

    // Strip nested Oberon comments by overwriting them with spaces so
    // identifier scanning still has the right line/column anchoring.
    int depth = 0;
    for (size_t i = 0; i + 1 < n; ) {
        if (depth == 0 && buf[i] == '(' && buf[i+1] == '*') {
            buf[i] = ' '; buf[i+1] = ' '; depth = 1; i += 2;
        } else if (depth > 0 && buf[i] == '(' && buf[i+1] == '*') {
            buf[i] = ' '; buf[i+1] = ' '; depth++; i += 2;
        } else if (depth > 0 && buf[i] == '*' && buf[i+1] == ')') {
            buf[i] = ' '; buf[i+1] = ' '; depth--; i += 2;
        } else {
            if (depth > 0 && buf[i] != '\n') buf[i] = ' ';
            i++;
        }
    }

    char *imp = strstr(buf, "IMPORT");
    if (!imp) return 0;
    char *q = imp + 6;
    int count = 0;
    while (*q && *q != ';' && count < max) {
        while (*q && (isspace((unsigned char)*q) || *q == ',')) q++;
        if (!*q || *q == ';') break;
        char name[MAX_LINK_NAME];
        int i = 0;
        while (*q && (isalnum((unsigned char)*q) || *q == '_') && i < MAX_LINK_NAME - 1) {
            name[i++] = *q++;
        }
        name[i] = 0;
        // alias `M := Real` — keep the actual module name.
        while (*q && isspace((unsigned char)*q)) q++;
        if (q[0] == ':' && q[1] == '=') {
            q += 2;
            while (*q && isspace((unsigned char)*q)) q++;
            i = 0;
            while (*q && (isalnum((unsigned char)*q) || *q == '_') && i < MAX_LINK_NAME - 1) {
                name[i++] = *q++;
            }
            name[i] = 0;
        }
        if (i > 0 && strcmp(name, "SYSTEM") != 0) {
            strncpy(out[count], name, MAX_LINK_NAME - 1);
            out[count][MAX_LINK_NAME - 1] = 0;
            count++;
        }
    }
    return count;
}

// True iff the module's .Mod (in user dir or runtime dir) is newer than
// its .smb / .o sitting next to it, or those outputs are missing.
static int needs_compile(const char *source_dir, const char *modname,
                         BOOLEAN want_wasm) {
    char mod_path[512];
    if (locate_module_source(source_dir, modname, mod_path, sizeof(mod_path)) != 0) {
        return 0;   // can't find source — caller will get import errors
    }
    // Use the .Mod's containing directory for the output check.
    char dir[512];
    int last_sep = -1;
    for (int i = 0; mod_path[i]; i++) {
        if (mod_path[i] == '/' || mod_path[i] == '\\') last_sep = i;
    }
    if (last_sep < 0) { dir[0] = 0; }
    else {
        size_t n = (size_t)(last_sep + 1);
        if (n >= sizeof(dir)) n = sizeof(dir) - 1;
        memcpy(dir, mod_path, n);
        dir[n] = 0;
    }
    char smb_path[512], o_path[512];
    snprintf(smb_path, sizeof(smb_path), "%s%s.smb", dir, modname);
    snprintf(o_path,   sizeof(o_path),   "%s%s.o",   dir, modname);
    struct stat mod_st, smb_st, o_st;
    if (stat(mod_path, &mod_st) != 0) return 0;
    if (stat(smb_path, &smb_st) != 0) return 1;
    if (stat(o_path,   &o_st)   != 0) return 1;
    if (mod_st.st_mtime > smb_st.st_mtime || mod_st.st_mtime > o_st.st_mtime) {
        return 1;
    }
    /* Target mismatch: peek at the .o's first 4 bytes to tell wasm
       (`\0asm`) from Mach-O / ELF. Force rebuild if it disagrees with
       the requested target. */
    FILE *fp = fopen(o_path, "rb");
    if (fp) {
        unsigned char magic[4] = {0};
        size_t n = fread(magic, 1, 4, fp);
        fclose(fp);
        if (n == 4) {
            BOOLEAN is_wasm = (magic[0] == 0 && magic[1] == 'a' &&
                                magic[2] == 's' && magic[3] == 'm');
            if (is_wasm != want_wasm) return 1;
        }
    }
    return 0;
}

static void derive_source_dir(const char *fname, char *out, size_t outsz) {
    int last = -1;
    for (int i = 0; fname[i]; i++) {
        if (fname[i] == '/' || fname[i] == '\\') last = i;
    }
    if (last >= 0) {
        size_t n = (size_t)(last + 1);
        if (n >= outsz) n = outsz - 1;
        memcpy(out, fname, n);
        out[n] = 0;
    } else {
        out[0] = 0;
    }
}

static int ensure_compiled(const char *self_argv0, const char *source_dir,
                           const char *name, const char *target,
                           char visited[][MAX_LINK_NAME], int *nv) {
    for (int i = 0; i < *nv; i++) {
        if (strcmp(visited[i], name) == 0) return 0;
    }
    if (*nv >= MAX_LINK_MODS) {
        fprintf(stderr, "oc: import graph too deep\n");
        return 1;
    }
    strncpy(visited[*nv], name, MAX_LINK_NAME - 1);
    visited[*nv][MAX_LINK_NAME - 1] = 0;
    (*nv)++;

    char imps[MAX_LINK_MODS][MAX_LINK_NAME];
    int nimp = scan_imports(source_dir, name, imps, MAX_LINK_MODS);
    for (int i = 0; i < nimp; i++) {
        if (ensure_compiled(self_argv0, source_dir, imps[i], target, visited, nv) != 0) {
            return 1;
        }
    }

    BOOLEAN want_wasm = target && strstr(target, "wasm");
    if (needs_compile(source_dir, name, want_wasm)) {
        char src_path[512];
        if (locate_module_source(source_dir, name, src_path, sizeof(src_path)) != 0) {
            return 0;   // not found anywhere — let the import phase complain
        }
        char cmd[1024];
        if (target) {
            snprintf(cmd, sizeof(cmd), "'%s' -target '%s' '%s'",
                     self_argv0, target, src_path);
        } else {
            snprintf(cmd, sizeof(cmd), "'%s' '%s'", self_argv0, src_path);
        }
        int rc = system(cmd);
        if (rc != 0) {
            fprintf(stderr, "oc: failed to compile %s (rc=%d)\n", name, rc);
            return rc ? rc : 1;
        }
    }
    return 0;
}

static int oc_link(const char *self_argv0, const char *output,
                   const char *entry, BOOLEAN include_runtime,
                   BOOLEAN shared, const char *target,
                   int n_extras, char **extras) {
    BOOLEAN is_wasm = target && strstr(target, "wasm");
    char modules[MAX_LINK_MODS][MAX_LINK_NAME];
    int  nmod = 0;
    char queue[MAX_LINK_MODS][MAX_LINK_NAME];
    int  qhead = 0, qtail = 0;

    strncpy(queue[qtail++], entry, MAX_LINK_NAME - 1);

    while (qhead < qtail) {
        const char *m = queue[qhead++];
        if (list_has(modules, nmod, m)) continue;
        if (nmod >= MAX_LINK_MODS) {
            fprintf(stderr, "oc: too many modules in transitive closure\n");
            return 1;
        }
        strncpy(modules[nmod], m, MAX_LINK_NAME - 1);
        modules[nmod][MAX_LINK_NAME - 1] = 0;
        nmod++;

        char path[512];
        const char *sd = GetSourceDir();
        snprintf(path, sizeof(path), "%s%s.deps", sd ? sd : "", m);
        FILE *f = fopen(path, "r");
        if (!f) continue;       // module has no recorded imports
        char line[MAX_LINK_NAME];
        while (fgets(line, sizeof(line), f)) {
            line[strcspn(line, "\r\n")] = 0;
            if (!line[0]) continue;
            if (qtail < MAX_LINK_MODS &&
                !list_has(queue, qtail, line) &&
                !list_has(modules, nmod, line)) {
                strncpy(queue[qtail], line, MAX_LINK_NAME - 1);
                queue[qtail][MAX_LINK_NAME - 1] = 0;
                qtail++;
            }
        }
        fclose(f);
    }

    char main_path[512] = "";
    const char *sd = GetSourceDir();
    if (!shared) {
        // Synthesize main.c next to the source dir for executables.
        // Besides invoking <entry>__init, this emits a static manifest
        // listing every module in the link closure — Modules_rt.c
        // consults it so `Modules.Load(name)` works without dlopen.
        // Required on wasm (no dynamic linking) and a convenient
        // alternative to dlopen on native.
        snprintf(main_path, sizeof(main_path), "%s.oc_main_%d.c",
                 sd ? sd : "", (int)getpid());
        FILE *mf = fopen(main_path, "w");
        if (!mf) {
            fprintf(stderr, "oc: cannot write %s\n", main_path);
            return 1;
        }
        fprintf(mf, "/* Auto-generated by oc — do not edit. */\n");
        fprintf(mf, "extern void oc_set_args(int, char **);\n");
        for (int i = 0; i < nmod; i++) {
            fprintf(mf, "extern void %s__init(void);\n", modules[i]);
            fprintf(mf, "extern char %s__exports[];\n", modules[i]);
        }
        fprintf(mf, "\n");
        fprintf(mf, "typedef struct {\n");
        fprintf(mf, "    const char *name;\n");
        fprintf(mf, "    void      (*init_fn)(void);\n");
        fprintf(mf, "    void       *exports;\n");
        fprintf(mf, "} OCModuleEntry;\n\n");
        fprintf(mf, "const OCModuleEntry oc_module_manifest[] = {\n");
        for (int i = 0; i < nmod; i++) {
            fprintf(mf, "    { \"%s\", %s__init, %s__exports },\n",
                    modules[i], modules[i], modules[i]);
        }
        fprintf(mf, "    { 0, 0, 0 }\n");
        fprintf(mf, "};\n\n");
        fprintf(mf,
            "int main(int argc, char **argv) {\n"
            "    oc_set_args(argc, argv);\n"
            "    %s__init();\n"
            "    return 0;\n"
            "}\n", entry);
        fclose(mf);
    }

    // Build the clang command line. Single-quoted args handle spaces.
    char cmd[8192];
    int p;
    if (is_wasm) {
        /* Static-only WASI build — wasm32 can't do dynamic linking the
         * way Mach-O does, so -shared is rejected upstream. We invoke
         * Homebrew's clang explicitly because macOS's /usr/bin/clang
         * has no WebAssembly backend. Paths are Homebrew defaults;
         * override via OC_WASM_CLANG / OC_WASI_SYSROOT /
         * OC_WASI_RESOURCE_DIR env vars. */
        const char *wclang = getenv("OC_WASM_CLANG");
        if (!wclang)  wclang  = "/opt/homebrew/opt/llvm/bin/clang";
        const char *sysroot = getenv("OC_WASI_SYSROOT");
        if (!sysroot) sysroot = "/opt/homebrew/opt/wasi-libc/share/wasi-sysroot";
        const char *resdir = getenv("OC_WASI_RESOURCE_DIR");
        if (!resdir)  resdir  = "/opt/homebrew/opt/wasi-runtimes/share/wasi-runtimes";
        p = snprintf(cmd, sizeof(cmd),
            "'%s' --target=%s --sysroot='%s' -resource-dir='%s' -o '%s' '%s'",
            wclang, target, sysroot, resdir, output, main_path);
    } else if (shared) {
        // -shared: produce a dylib whose unresolved symbols are looked
        // up by dyld at load time against the host process. The
        // runtime / imports need to be statically linked into the host
        // (or loaded ahead of us).
        p = snprintf(cmd, sizeof(cmd),
            "clang -shared -Wl,-undefined,dynamic_lookup -o '%s'", output);
    } else {
        p = snprintf(cmd, sizeof(cmd),
            "clang -o '%s' '%s'", output, main_path);
    }
    if (shared) {
        // Shared mode: only the entry module's .o goes in the dylib.
        // Imports stay as undefined symbols resolved at load time —
        // either by another loaded dylib or by the host process.
        char obj[512];
        if (locate_module_object(sd ? sd : "", entry, obj, sizeof(obj)) == 0) {
            p += snprintf(cmd + p, sizeof(cmd) - p, " '%s'", obj);
        }
    } else {
        for (int i = 0; i < nmod; i++) {
            char obj[512];
            if (locate_module_object(sd ? sd : "", modules[i], obj, sizeof(obj)) == 0) {
                p += snprintf(cmd + p, sizeof(cmd) - p, " '%s'", obj);
            } else {
                fprintf(stderr,
                    "oc: warning: %s.o missing — module not linked (compile %s.Mod first?)\n",
                    modules[i], modules[i]);
            }
        }
    }
    if (include_runtime && !shared) {
        // Runtime is statically linked into the host. Shared modules
        // resolve oc_alloc / oc_retain / oc_release against the host at
        // load time via -undefined dynamic_lookup.
        char rt_path[1024];
        if (find_runtime_source(self_argv0, target, rt_path, sizeof(rt_path)) == 0) {
            p += snprintf(cmd + p, sizeof(cmd) - p, " '%s'", rt_path);
        } else {
            fprintf(stderr,
                "oc: warning: runtime.c not found near %s — "
                "ARC symbols (oc_alloc / oc_retain / oc_release) will be "
                "unresolved. Pass --no-runtime to silence this and supply "
                "your own implementation.\n", self_argv0);
        }
        // For every module in the transitive import closure, look for
        // an <Mod>_rt.c sidecar in the (target-aware) runtime modules
        // directory and link it in. This is how Modules / Files /
        // Kernel / etc. pick up their strong overrides without the
        // user having to remember.
        for (int i = 0; i < nmod; i++) {
            char rt_name[256], rt_path[1024];
            snprintf(rt_name, sizeof(rt_name), "%s_rt.c", modules[i]);
            if (find_runtime_file(self_argv0, rt_name, target, rt_path, sizeof(rt_path)) == 0) {
                p += snprintf(cmd + p, sizeof(cmd) - p, " '%s'", rt_path);
            }
        }
    }
    for (int i = 0; i < n_extras; i++) {
        p += snprintf(cmd + p, sizeof(cmd) - p, " '%s'", extras[i]);
    }

    int rc = system(cmd);
    if (main_path[0]) unlink(main_path);
    if (rc != 0) {
        fprintf(stderr, "oc: link failed (clang exit %d)\n", rc);
        return rc ? rc : 1;
    }
    printf("Linked %s\n", output);
    return 0;
}

static void modid_from_filename(const char *fname, char *out, size_t outsz) {
    const char *base = strrchr(fname, '/');
    base = base ? base + 1 : fname;
    const char *bs = strrchr(base, '\\');
    if (bs) base = bs + 1;
    size_t i = 0;
    while (base[i] && base[i] != '.' && i + 1 < outsz) {
        out[i] = base[i];
        i++;
    }
    out[i] = 0;
}

int main(int argc, char **argv) {
    const char *filename = NULL;
    const char *output = NULL;
    char *extras[64];
    int n_extras = 0;
    bool forceNewSF = false;
    bool emit_obj = true;       // override with -S
    bool do_link = false;       // set by -o
    bool include_runtime = true;// override with --no-runtime
    bool shared = false;        // -shared: build a dylib instead of an exe
    const char *target = NULL;  // -target wasm32-wasi: cross-compile
    int i;

    if (argc < 2) {
        printf("Usage: %s [flags] <module.Mod> [extras...]\n", argv[0]);
        printf("  -s              Force new symbol file\n");
        printf("  -I<dir>         Add symbol file search path\n");
        printf("  -c              Compile only (default; no link)\n");
        printf("  -S              Emit only .ll, skip .o\n");
        printf("  -o <prog>       Auto-link transitive imports into native binary\n");
        printf("  -shared         Produce a .dylib (load via Modules.Load at runtime)\n");
        printf("  --no-runtime    Don't auto-include oberon/runtime.c in the link\n");
        printf("  extras          Passed through to clang (e.g. Out_rt.c, -lm)\n");
        return 1;
    }

    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-s") == 0 || strcmp(argv[i], "/s") == 0) {
            forceNewSF = true;
        } else if (strcmp(argv[i], "-c") == 0) {
            do_link = false;        // explicit no-link (also the default)
        } else if (strcmp(argv[i], "-S") == 0) {
            emit_obj = false;
            do_link = false;        // can't link without object code
        } else if (strcmp(argv[i], "--no-runtime") == 0) {
            include_runtime = false;
        } else if (strcmp(argv[i], "-shared") == 0) {
            shared = true;
        } else if (strcmp(argv[i], "-target") == 0) {
            if (i + 1 < argc) target = argv[++i];
            else { fprintf(stderr, "oc: -target expects an argument\n"); return 1; }
        } else if (strncmp(argv[i], "-target=", 8) == 0) {
            target = argv[i] + 8;
        } else if (strcmp(argv[i], "-o") == 0) {
            if (i + 1 < argc) { output = argv[++i]; do_link = true; }
            else { fprintf(stderr, "oc: -o expects an argument\n"); return 1; }
        } else if (strncmp(argv[i], "-I", 2) == 0) {
            if (argv[i][2] != '\0') {
                AddSearchPath(&argv[i][2]);
            } else if (i + 1 < argc) {
                AddSearchPath(argv[++i]);
            }
        } else if (filename == NULL && strstr(argv[i], ".Mod")) {
            filename = argv[i];
        } else {
            if (n_extras < 64) extras[n_extras++] = argv[i];
        }
    }

    // -S without -o is fine (just inspect IR). -S with -o is contradictory
    // — we need .o files to link. Ignore the link request in that case.
    if (!emit_obj && do_link) {
        fprintf(stderr, "oc: -S and -o are incompatible (need .o to link)\n");
        return 1;
    }

    // Accept short target aliases. "wasm32" or "wasm" map to
    // wasm32-wasip1 — wasi-libc's current preferred name.
    if (target) {
        if (strcmp(target, "wasm32") == 0 || strcmp(target, "wasm") == 0) {
            target = "wasm32-wasip1";
        }
        ORG_SetTargetTriple(target);
    }

    // Locate the runtime modules directory (oberon/ next to bin/oc) and
    // add it as a symbol-file search path so importers can find Out.smb,
    // Modules.smb, etc., without explicit -I flags.
    resolve_runtime_dir(argv[0], target);
    if (RuntimeDir[0]) AddSearchPath(RuntimeDir);

    if (filename == NULL) {
        printf("Usage: %s [-s] [-I<dir>] [-o <prog>] <module.Mod> [extras...]\n", argv[0]);
        return 1;
    }

    // When -o is set, recursively compile any stale imports BEFORE we
    // initialise the front-end for the main module — the imports need
    // their .smb files in place by the time we parse the IMPORT clause.
    if (do_link) {
        char source_dir_buf[512];
        char entry_modid[64];
        derive_source_dir(filename, source_dir_buf, sizeof(source_dir_buf));
        modid_from_filename(filename, entry_modid, sizeof(entry_modid));
        char visited[MAX_LINK_MODS][MAX_LINK_NAME];
        int nv = 0;
        char main_imps[MAX_LINK_MODS][MAX_LINK_NAME];
        int nimp = scan_imports(source_dir_buf, entry_modid, main_imps, MAX_LINK_MODS);
        for (int j = 0; j < nimp; j++) {
            if (ensure_compiled(argv[0], source_dir_buf,
                                main_imps[j], target, visited, &nv) != 0) {
                return 1;
            }
        }
    }

    printf("Oberon LLVM Compiler (self-hosted)\n");

    ORP__init();   /* runs the Oberon module init chain */
    ORG_SetEmitFlags(TRUE, emit_obj);
    derive_source_dir(filename, main_source_dir, sizeof(main_source_dir));
    ORG_SetSourceDir(main_source_dir);
    ORP__Compile(filename, (INTEGER)strlen(filename) + 1, forceNewSF);

    if (ORS__errcnt > 0) {
        printf("Compilation failed with %d errors\n", ORS__errcnt);
        return 1;
    }
    printf("Compilation successful\n");

    if (do_link) {
        char modid_buf[64];
        modid_from_filename(filename, modid_buf, sizeof(modid_buf));
        return oc_link(argv[0], output, modid_buf,
                       include_runtime, shared, target, n_extras, extras);
    }
    return 0;
}
