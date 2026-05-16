/* runtime/wasm/Files_rt.c — Files for the browser host.
 *
 * Whole-file buffering on the wasm side (same scheme as the posix
 * impl), with the actual storage living on a server reached via
 * JS-imported file primitives:
 *
 *     "files" module imports — declared below, implemented by
 *     tests/wasm/files-shim.js (or a TypeScript equivalent) which
 *     issues synchronous XMLHttpRequests against /api/files/...
 *
 * Async fetch() would be the modern choice but isn't reachable from
 * a synchronous wasm call without SharedArrayBuffer + Atomics.wait
 * or JS Promise Integration. Sync XHR is deprecated but works
 * everywhere and the only place we use it is once on Old (read full
 * file into a buffer) and once on Register / Close (push buffer
 * back). Read/Write are local buffer operations after that — the
 * usual per-byte hot path never crosses the wasm-JS boundary. */
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

/* Layout matches the compiler emission for Files.FileDesc /
 * Files.Rider — see runtime/posix/Files_rt.c for the derivation. */
typedef struct FileDesc {
    void   *_tag;
    int64_t _rc;
    int64_t handle;       /* (FileBuf *) cast to int64 */
    char    name[256];
    int     length;
    int     date;
    int8_t  registered;
} FileDesc;

typedef struct Rider {
    void     *_tag;
    int64_t   _rc;
    int8_t    eof;
    int       res;
    FileDesc *file;
    int       pos;
} Rider;

typedef struct FileBuf {
    uint8_t *data;
    int      len;
    int      cap;
    int      dirty;
} FileBuf;

extern FileDesc *Files__NewFileDesc(void);
extern void      oc_retain(void *p);
extern void      oc_release(void *p);

/* ---- JS imports ------------------------------------------------- */

#define FILES_IMPORT(name) \
    __attribute__((import_module("files"), import_name(#name)))

/* js_read(name, name_len, buf_out_addr*, len_out*, date_out*)
 *   Sync GET. On 200, the shim allocates a wasm-side buffer big
 *   enough to hold the bytes and returns its address + length and
 *   the file's mtime (seconds since epoch).
 *   Returns 0 on success, 1 on not-found, 2 on other error.
 *
 * The buffer pointer must point to memory the wasm side owns —
 * shims call back into the wasm-exported `oc_wasm_alloc` to get a
 * block of the right size before writing decoded bytes into it. */
FILES_IMPORT(read)
extern int js_files_read(const char *name, int name_len,
                         int *buf_addr_out, int *len_out, int *date_out);

/* js_write(name, name_len, buf_addr, len) — sync PUT.
 *   Returns 0 on success, non-zero on error. */
FILES_IMPORT(write)
extern int js_files_write(const char *name, int name_len,
                          const uint8_t *data, int len);

/* js_delete(name, name_len) — sync DELETE.
 *   Returns 0 on success, 2 on not-found, 1 on other error. */
FILES_IMPORT(delete)
extern int js_files_delete(const char *name, int name_len);

/* js_rename(old, old_len, new, new_len) — sync POST /rename.
 *   Returns 0 on success, 2 on not-found, 1 on other error. */
FILES_IMPORT(rename)
extern int js_files_rename(const char *oldn, int old_len,
                           const char *newn, int new_len);

/* js_exists(name, name_len) — sync HEAD.
 *   Returns 1 if present, 0 otherwise. */
FILES_IMPORT(exists)
extern int js_files_exists(const char *name, int name_len);

/* js_mkdir(name, name_len) — sync POST /mkdir.
 *   Returns 0 on success, non-zero on error. */
FILES_IMPORT(mkdir)
extern int js_files_mkdir(const char *name, int name_len);

/* ---- wasm-side allocator exposed to JS -------------------------- */

/* JS calls back into this from files_read to obtain a buffer for
 * the file body. The caller (Files__Old) hands the resulting
 * pointer to the FileBuf and the wasm side owns it forever after. */
__attribute__((export_name("oc_wasm_alloc")))
void *oc_wasm_alloc(int n) {
    if (n <= 0) return NULL;
    return malloc((size_t)n);
}

/* ---- helpers ---------------------------------------------------- */

static FileBuf *new_buf(void) {
    return (FileBuf *)calloc(1, sizeof(FileBuf));
}

static void grow_buf(FileBuf *b, int need) {
    if (need <= b->cap) return;
    int newcap = b->cap ? b->cap : 64;
    while (newcap < need) newcap *= 2;
    b->data = realloc(b->data, (size_t)newcap);
    if (newcap > b->cap) memset(b->data + b->cap, 0, (size_t)(newcap - b->cap));
    b->cap = newcap;
}

/* Copy an open-array CHAR (ptr,len) into a NUL-terminated buffer. */
static void copy_name(const char *src, int src_len, char *dst, size_t cap) {
    size_t n = 0;
    while (n + 1 < cap && (int)n < src_len && src[n] != 0) {
        dst[n] = src[n]; n++;
    }
    dst[n] = 0;
}

static int name_strlen(const char *p, int max_len) {
    int n = 0;
    while (n < max_len && p[n] != 0) n++;
    return n;
}

/* ---- File lifecycle -------------------------------------------- */

FileDesc *Files__Old(const char *name, int name_len) {
    int buf_addr = 0, len = 0, date = 0;
    int rc = js_files_read(name, name_len, &buf_addr, &len, &date);
    if (rc != 0 || buf_addr == 0) return NULL;

    FileDesc *f = Files__NewFileDesc();
    if (!f) return NULL;
    FileBuf *b = new_buf();
    b->data = (uint8_t *)(intptr_t)buf_addr;
    b->len  = len;
    b->cap  = len;
    b->dirty = 0;
    f->handle = (int64_t)(intptr_t)b;
    copy_name(name, name_len, f->name, sizeof(f->name));
    f->length = len;
    f->date   = date;
    f->registered = 1;
    return f;
}

FileDesc *Files__New(const char *name, int name_len) {
    FileDesc *f = Files__NewFileDesc();
    if (!f) return NULL;
    FileBuf *b = new_buf();
    f->handle = (int64_t)(intptr_t)b;
    copy_name(name, name_len, f->name, sizeof(f->name));
    f->length = 0;
    f->date   = 0;
    f->registered = 0;
    return f;
}

void Files__Register(FileDesc *f) {
    if (!f) return;
    FileBuf *b = (FileBuf *)(intptr_t)f->handle;
    if (!b) return;
    int nlen = name_strlen(f->name, (int)sizeof(f->name));
    if (js_files_write(f->name, nlen, b->data, b->len) == 0) {
        b->dirty = 0;
        f->registered = 1;
    }
}

void Files__Close(FileDesc *f) {
    if (!f) return;
    FileBuf *b = (FileBuf *)(intptr_t)f->handle;
    if (!b) return;
    if (f->registered && b->dirty) {
        int nlen = name_strlen(f->name, (int)sizeof(f->name));
        if (js_files_write(f->name, nlen, b->data, b->len) == 0) {
            b->dirty = 0;
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
    *res = js_files_delete(name, name_len);
}

void Files__Rename(const char *oldn, int old_len,
                   const char *newn, int new_len, int *res) {
    *res = js_files_rename(oldn, old_len, newn, new_len);
}

int Files__Length(FileDesc *f) {
    if (!f) return 0;
    FileBuf *b = (FileBuf *)(intptr_t)f->handle;
    return b ? b->len : 0;
}

int Files__Date(FileDesc *f) {
    return f ? f->date : 0;
}

int Files__Exists(const char *name, int name_len) {
    return js_files_exists(name, name_len);
}

void Files__MakeDir(const char *name, int name_len, int *res) {
    *res = js_files_mkdir(name, name_len);
}

/* ---- Rider ------------------------------------------------------ */

void Files__Set(Rider *r, FileDesc *f, int pos) {
    if (!r) return;
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
    oc_retain(r->file);
    return r->file;
}

/* ---- Read primitives ------------------------------------------- */

void Files__ReadByte(Rider *r, int8_t *x) {
    if (!r || !r->file) { if (x) *x = 0; return; }
    FileBuf *b = (FileBuf *)(intptr_t)r->file->handle;
    if (!b || r->pos >= b->len) {
        if (x) *x = 0;
        r->eof = 1;
        return;
    }
    if (x) *x = (int8_t)b->data[r->pos];
    r->pos++;
}

void Files__ReadBytes(Rider *r, uint8_t *x, int x_len, int n) {
    for (int i = 0; i < n; i++) {
        int8_t bv;
        Files__ReadByte(r, &bv);
        if (i < x_len) x[i] = (uint8_t)bv;
    }
}

void Files__Read(Rider *r, char *ch) {
    int8_t bv;
    Files__ReadByte(r, &bv);
    if (ch) *ch = (char)bv;
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
        if (i < out_len - 1) out[i++] = c;
        Files__Read(R, &c);
    }
    out[i] = 0;
}

void Files__ReadNum(Rider *R, int *x) {
    int n = 32, y = 0;
    int8_t bv;
    Files__ReadByte(R, &bv);
    while ((uint8_t)bv >= 0x80) {
        unsigned add = (unsigned)((uint8_t)bv - 0x80);
        unsigned u = ((unsigned)y + add);
        y = (int)((u >> 7) | (u << 25));
        n -= 7;
        Files__ReadByte(R, &bv);
    }
    if (n <= 4) {
        unsigned add = ((uint8_t)bv) & 0xF;
        unsigned u = (unsigned)y + add;
        *x = (int)((u >> 4) | (u << 28));
    } else {
        unsigned u = (unsigned)y + (uint8_t)bv;
        unsigned r = (u >> 7) | (u << 25);
        *x = (int)((int)r >> (n - 7));
    }
}

/* ---- Write primitives ------------------------------------------ */

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

void Files__WriteByte(Rider *r, int8_t x) { put_byte(r, (uint8_t)x); }

void Files__WriteBytes(Rider *r, const uint8_t *x, int x_len, int n) {
    (void)x_len;
    for (int i = 0; i < n; i++) put_byte(r, x[i]);
}

void Files__Write(Rider *r, char ch) { put_byte(r, (uint8_t)ch); }

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
