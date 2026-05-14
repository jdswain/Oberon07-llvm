/* FileDir_rt.c — POSIX strong overrides for FileDir.Mod. */
#include <dirent.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

/* FileName is a fixed-size ARRAY 32 OF CHAR — Oberon passes it as a
 * single pointer to the array, with the length implicit (32). NUL-
 * terminated within the buffer as long as the source name <= 31 chars. */
#define FN_LEN 32

void FileDir__Search(const char *name, int *A) {
    char path[FN_LEN + 1];
    int i = 0;
    while (i < FN_LEN && name[i] != 0) { path[i] = name[i]; i++; }
    path[i] = 0;
    *A = (access(path, F_OK) == 0) ? 1 : 0;
}

void FileDir__Insert(const char *name, int fad) {
    (void)name; (void)fad;
}

void FileDir__Delete(const char *name, int *fad) {
    char path[FN_LEN + 1];
    int i = 0;
    while (i < FN_LEN && name[i] != 0) { path[i] = name[i]; i++; }
    path[i] = 0;
    if (unlink(path) == 0) *fad = 1;
    else *fad = 0;
}

/* EntryHandler signature on the C side: name is a FileName (fixed-size
 * ARRAY 32 OF CHAR) → single ptr; sec is i32; continue is VAR BOOLEAN. */
typedef void (*EntryHandler)(const char *name_ptr, int sec, int8_t *cont);

/* `prefix: ARRAY OF CHAR` is an open-array param → ABI is (ptr, len). */
void FileDir__Enumerate(const char *prefix, int prefix_len,
                        EntryHandler proc) {
    if (!proc) return;
    DIR *d = opendir(".");
    if (!d) return;
    int prefix_n = 0;
    while (prefix_n < prefix_len && prefix[prefix_n] != 0) prefix_n++;

    int8_t cont = 1;
    struct dirent *ent;
    while (cont && (ent = readdir(d))) {
        if (ent->d_name[0] == '.') continue;       /* skip ., .., dotfiles */
        if (prefix_n > 0 && strncmp(ent->d_name, prefix, (size_t)prefix_n) != 0) continue;

        /* Pass name as a 32-byte FileName buffer per PO ABI. */
        char fn[FN_LEN];
        size_t l = strlen(ent->d_name);
        if (l > FN_LEN - 1) l = FN_LEN - 1;
        memcpy(fn, ent->d_name, l);
        memset(fn + l, 0, FN_LEN - l);
        proc(fn, 1, &cont);
    }
    closedir(d);
}

void FileDir__Init(void) {}
void FileDir__init(void) {}
