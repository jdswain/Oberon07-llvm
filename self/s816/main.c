/*
 * main.c — driver for the self-hosted 65C816 Oberon compiler (oc816).
 *
 * Much simpler than the LLVM driver: the 816 backend (ORG.Mod) is pure
 * Oberon and emits a self-contained relocatable ".816" module directly,
 * so there is no LLVM plumbing and no link step. The driver only parses
 * the command line, runs the Oberon module init chain, registers symbol-
 * file search paths, and calls ORP.Compile.
 *
 * The compiler proper is the shared frontend ORS/ORB/ORP plus the 816
 * backend OCG/ORG, all compiled to native objects by the stage-0 oc and
 * linked with the POSIX runtime (Files/Out/Errors + runtime.c).
 */

#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>

typedef int32_t INTEGER;
typedef int64_t LONGINT;
typedef bool    BOOLEAN;
#define TRUE  true
#define FALSE false

/* Oberon entry points (mangled names, shared with the LLVM build). */
extern void    ORP__init(void);                                   /* init chain */
extern void    ORP__Compile(const char *name, INTEGER len, BOOLEAN force);
extern INTEGER ORS__errcnt;
extern void    ORB__AddSearchPath(const char *path, INTEGER len);

/* Register a .smb search path. ORP__init must have run first (the ORB
 * module body zeroes the search-path table), so force the run-once init
 * chain before registering. */
static void AddSearchPath(const char *path) {
    ORP__init();
    ORB__AddSearchPath(path, (INTEGER)strlen(path) + 1);
}

static void usage(const char *argv0) {
    printf("Usage: %s <module.Mod> [-s] [-I<dir>] [-I <dir>]\n", argv0);
    printf("  -s          Force new symbol file\n");
    printf("  -I<dir>     Add symbol-file (.smb) search path\n");
}

int main(int argc, char **argv) {
    const char *filename = NULL;
    BOOLEAN force = FALSE;
    int i;

    if (argc < 2) { usage(argv[0]); return 1; }

    /* Flags may appear before or after the filename. */
    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-s") == 0 || strcmp(argv[i], "/s") == 0) {
            force = TRUE;
        } else if (strncmp(argv[i], "-I", 2) == 0) {
            if (argv[i][2] != '\0') {
                AddSearchPath(&argv[i][2]);
            } else if (i + 1 < argc) {
                AddSearchPath(argv[++i]);
            }
        } else if (filename == NULL) {
            filename = argv[i];
        }
    }

    if (filename == NULL) { usage(argv[0]); return 1; }

    printf("Oberon 65C816 Compiler (self-hosted)\n");

    ORP__init();   /* runs the Oberon module init chain */
    ORP__Compile(filename, (INTEGER)strlen(filename) + 1, force);

    if (ORS__errcnt > 0) {
        printf("Compilation failed with %d errors\n", ORS__errcnt);
        return 1;
    }
    printf("Compilation successful\n");
    return 0;
}
