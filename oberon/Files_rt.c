/* Files_rt.c — POSIX-passthrough strong overrides for Files.Mod.
 *
 * Each Oberon File holds the entire file content in an in-memory growable
 * buffer (FileBuf). Old() reads the host file into the buffer; New()
 * starts with an empty buffer and a deferred name. Register() / Close()
 * flush the buffer back to disk under the file's name. Reads and writes
 * are simple byte-level operations on the buffer.
 *
 * This trades streaming and unbounded-size support for radical simplicity:
 * a complete File is one C malloc, the host filesystem is the directory,
 * and there are no pages, sectors, B-trees or buffer caches. Suitable for
 * the "edit a few hundred KB of source files" workloads typical of
 * Oberon-style programs; not for video editing.
 */
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <time.h>

/* Match the FileDesc layout the compiler emits:
 *   { ptr _tag, i64 _rc, i64 handle, [32 x i8] name,
 *     i32 length, i32 date, i1 registered } */
typedef struct FileDesc {
    void   *_tag;
    int64_t _rc;
    int64_t handle;       /* (FileBuf *) cast to int64 */
    char    name[32];
    int     length;
    int     date;
    int8_t  registered;   /* i1 stored as i8 */
} FileDesc;

/* Match the Rider layout the compiler emits:
 *   { ptr _tag, i64 _rc, i1 eof, i32 res, ptr file, i32 pos }
 * Natural C alignment reproduces LLVM's struct layout: pad after eof
 * (i8) to align res (i32), then to align file (ptr).  Total 40 bytes. */
typedef struct Rider {
    void     *_tag;
    int64_t   _rc;
    int8_t    eof;
    int       res;
    FileDesc *file;
    int       pos;
} Rider;

/* In-memory buffer holding the file content. Owned by FileDesc.handle. */
typedef struct FileBuf {
    uint8_t *data;
    int      len;
    int      cap;
    int      dirty;
} FileBuf;

extern FileDesc *Files__NewFileDesc(void);
extern void      oc_retain(void *p);
extern void      oc_release(void *p);

static FileBuf *new_buf(void) {
    FileBuf *b = calloc(1, sizeof(FileBuf));
    return b;
}

static void free_buf(FileBuf *b) {
    if (!b) return;
    free(b->data);
    free(b);
}

static void grow_buf(FileBuf *b, int need) {
    if (need <= b->cap) return;
    int newcap = b->cap ? b->cap : 64;
    while (newcap < need) newcap *= 2;
    b->data = realloc(b->data, (size_t)newcap);
    if (newcap > b->cap) memset(b->data + b->cap, 0, (size_t)(newcap - b->cap));
    b->cap = newcap;
}

/* Copy an open-array CHAR (ptr, len) into a NUL-terminated path buffer. */
static void copy_name(const char *src, int src_len, char *dst, size_t cap) {
    size_t n = 0;
    while (n + 1 < cap && (int)n < src_len && src[n] != 0) {
        dst[n] = src[n]; n++;
    }
    dst[n] = 0;
}

/* Read entire host file into a fresh FileBuf. Returns NULL on ENOENT. */
static FileBuf *read_file(const char *path, int *date_out) {
    struct stat st;
    if (stat(path, &st) != 0) return NULL;
    FILE *fp = fopen(path, "rb");
    if (!fp) return NULL;
    FileBuf *b = new_buf();
    grow_buf(b, (int)st.st_size + 1);
    size_t got = fread(b->data, 1, (size_t)st.st_size, fp);
    fclose(fp);
    b->len = (int)got;
    if (date_out) *date_out = (int)st.st_mtime;
    return b;
}

static int write_file(const char *path, const FileBuf *b) {
    FILE *fp = fopen(path, "wb");
    if (!fp) return -1;
    if (b->len > 0) {
        size_t wrote = fwrite(b->data, 1, (size_t)b->len, fp);
        if ((int)wrote != b->len) { fclose(fp); return -1; }
    }
    fclose(fp);
    return 0;
}

/* ---- File lifecycle ---- */

FileDesc *Files__Old(const char *name, int name_len) {
    char path[PATH_MAX];
    copy_name(name, name_len, path, sizeof(path));
    if (!path[0]) return NULL;
    int date = 0;
    FileBuf *b = read_file(path, &date);
    if (!b) return NULL;
    FileDesc *f = Files__NewFileDesc();
    if (!f) { free_buf(b); return NULL; }
    f->handle = (int64_t)(intptr_t)b;
    strncpy(f->name, path, sizeof(f->name) - 1);
    f->name[sizeof(f->name) - 1] = 0;
    f->length = b->len;
    f->date = date;
    f->registered = 1;
    return f;
}

FileDesc *Files__New(const char *name, int name_len) {
    char path[PATH_MAX];
    copy_name(name, name_len, path, sizeof(path));
    FileDesc *f = Files__NewFileDesc();
    if (!f) return NULL;
    FileBuf *b = new_buf();
    f->handle = (int64_t)(intptr_t)b;
    strncpy(f->name, path, sizeof(f->name) - 1);
    f->name[sizeof(f->name) - 1] = 0;
    f->length = 0;
    f->date = (int)time(NULL);
    f->registered = 0;
    return f;
}

void Files__Register(FileDesc *f) {
    if (!f) return;
    FileBuf *b = (FileBuf *)(intptr_t)f->handle;
    if (!b) return;
    if (write_file(f->name, b) == 0) {
        b->dirty = 0;
        f->registered = 1;
        f->date = (int)time(NULL);
    }
}

void Files__Close(FileDesc *f) {
    if (!f) return;
    FileBuf *b = (FileBuf *)(intptr_t)f->handle;
    if (!b) return;
    if (f->registered && b->dirty) {
        if (write_file(f->name, b) == 0) {
            b->dirty = 0;
            f->date = (int)time(NULL);
        }
    }
}

void Files__Purge(FileDesc *f) {
    if (!f) return;
    FileBuf *b = (FileBuf *)(intptr_t)f->handle;
    if (!b) return;
    b->len = 0;
    b->dirty = 1;
    f->length = 0;
}

void Files__Delete(const char *name, int name_len, int *res) {
    char path[PATH_MAX];
    copy_name(name, name_len, path, sizeof(path));
    if (unlink(path) == 0) *res = 0;
    else if (errno == ENOENT) *res = 2;
    else *res = 1;
}

void Files__Rename(const char *oldn, int old_len,
                   const char *newn, int new_len, int *res) {
    char op[PATH_MAX], np[PATH_MAX];
    copy_name(oldn, old_len, op, sizeof(op));
    copy_name(newn, new_len, np, sizeof(np));
    if (rename(op, np) == 0) *res = 0;
    else if (errno == ENOENT) *res = 2;
    else *res = 1;
}

int Files__Length(FileDesc *f) {
    if (!f) return 0;
    FileBuf *b = (FileBuf *)(intptr_t)f->handle;
    return b ? b->len : 0;
}

int Files__Date(FileDesc *f) {
    return f ? f->date : 0;
}

/* ---- Rider ---- */

void Files__Set(Rider *r, FileDesc *f, int pos) {
    if (!r) return;
    /* Manual ARC dance: r->file := f. */
    if (f) oc_retain(f);
    if (r->file) oc_release(r->file);
    r->file = f;
    r->eof = 0;
    r->res = 0;
    r->pos = pos < 0 ? 0 : pos;
}

int Files__Pos(Rider *r) {
    return r ? r->pos : 0;
}

FileDesc *Files__Base(Rider *r) {
    if (!r || !r->file) return NULL;
    /* Compiler treats pointer-typed call results as +1 owned and emits a
     * matching release at the call site. Retain so the refcount math
     * balances. */
    oc_retain(r->file);
    return r->file;
}

/* ---- Read primitives ---- */

void Files__ReadByte(Rider *r, int8_t *x) {
    if (!r || !r->file) { if (x) *x = 0; return; }
    FileBuf *b = (FileBuf *)(intptr_t)r->file->handle;
    if (!b || r->pos >= b->len) {
        if (x) *x = 0;
        if (r) r->eof = 1;
        return;
    }
    if (x) *x = (int8_t)b->data[r->pos];
    r->pos++;
}

void Files__ReadBytes(Rider *r, uint8_t *x, int x_len, int n) {
    (void)x_len;
    for (int i = 0; i < n; i++) {
        int8_t b;
        Files__ReadByte(r, &b);
        if (i < x_len) x[i] = (uint8_t)b;
    }
}

void Files__Read(Rider *r, char *ch) {
    int8_t b;
    Files__ReadByte(r, &b);
    if (ch) *ch = (char)b;
}

void Files__ReadInt(Rider *R, int *x) {
    int8_t b0, b1, b2, b3;
    Files__ReadByte(R, &b0);
    Files__ReadByte(R, &b1);
    Files__ReadByte(R, &b2);
    Files__ReadByte(R, &b3);
    *x = ((uint8_t)b0)
       | ((uint32_t)(uint8_t)b1 << 8)
       | ((uint32_t)(uint8_t)b2 << 16)
       | ((uint32_t)(uint8_t)b3 << 24);
}

void Files__ReadString(Rider *R, char *out, int out_len) {
    if (out_len <= 0) return;
    int i = 0; char c;
    Files__Read(R, &c);
    while (c != 0) {
        if (i < out_len - 1) { out[i++] = c; }
        Files__Read(R, &c);
    }
    out[i] = 0;
}

void Files__ReadNum(Rider *R, int *x) {
    int n = 32, y = 0;
    int8_t b;
    Files__ReadByte(R, &b);
    while ((uint8_t)b >= 0x80) {
        unsigned add = (unsigned)((uint8_t)b - 0x80);
        unsigned u = ((unsigned)y + add);
        /* ROR(u, 7) = (u >> 7) | (u << 25) */
        y = (int)((u >> 7) | (u << 25));
        n -= 7;
        Files__ReadByte(R, &b);
    }
    if (n <= 4) {
        unsigned add = ((uint8_t)b) & 0xF;
        unsigned u = (unsigned)y + add;
        *x = (int)((u >> 4) | (u << 28));
    } else {
        unsigned u = (unsigned)y + (uint8_t)b;
        unsigned r = (u >> 7) | (u << 25);
        *x = (int)((int)r >> (n - 7));   /* arithmetic shift right */
    }
}

/* ---- Write primitives ---- */

static void put_byte(Rider *r, uint8_t v) {
    if (!r || !r->file) return;
    FileBuf *b = (FileBuf *)(intptr_t)r->file->handle;
    if (!b) return;
    grow_buf(b, r->pos + 1);
    b->data[r->pos] = v;
    r->pos++;
    if (r->pos > b->len) b->len = r->pos;
    b->dirty = 1;
    r->file->length = b->len;
}

void Files__WriteByte(Rider *r, int8_t x) {
    put_byte(r, (uint8_t)x);
}

void Files__WriteBytes(Rider *r, const uint8_t *x, int x_len, int n) {
    (void)x_len;
    for (int i = 0; i < n; i++) put_byte(r, x[i]);
}

void Files__Write(Rider *r, char ch) {
    put_byte(r, (uint8_t)ch);
}

void Files__WriteInt(Rider *R, int x) {
    put_byte(R, (uint8_t)(x & 0xFF));
    put_byte(R, (uint8_t)((x >> 8) & 0xFF));
    put_byte(R, (uint8_t)((x >> 16) & 0xFF));
    put_byte(R, (uint8_t)((x >> 24) & 0xFF));
}

void Files__WriteString(Rider *R, const char *s, int s_len) {
    int i = 0;
    while (i < s_len && s[i] != 0) {
        put_byte(R, (uint8_t)s[i]);
        i++;
    }
    put_byte(R, 0);
}

void Files__WriteNum(Rider *R, int x) {
    while (x < -0x40 || x >= 0x40) {
        put_byte(R, (uint8_t)((x & 0x7F) | 0x80));
        x >>= 7;
    }
    put_byte(R, (uint8_t)(x & 0x7F));
}

void Files__init(void) {}
