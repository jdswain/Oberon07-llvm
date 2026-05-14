/* runtime/wasm/Files_rt.c — placeholder Files implementation for the
 * wasm runtime. Returns NIL / non-zero res for every call so callers
 * see "no host filesystem" cleanly rather than crashing.
 *
 * Two real implementations are planned:
 *   - WASI-based: most of the POSIX impl in runtime/posix/Files_rt.c
 *     would Just Work under wasi-libc — fopen / fread / fwrite /
 *     stat / unlink / rename / mkdir are all WASI-mappable. Splitting
 *     it out lets us diverge for the browser case.
 *   - Browser-based: the long-term target. Calls into a JS shim that
 *     proxies file ops to a backend server over fetch(); the wasm
 *     never touches a real filesystem.
 */
#include <stdint.h>

typedef struct FileDesc FileDesc;
typedef struct Rider    Rider;

FileDesc *Files__Old(const char *name, int name_len) {
    (void)name; (void)name_len; return 0;
}
FileDesc *Files__New(const char *name, int name_len) {
    (void)name; (void)name_len; return 0;
}
void Files__Register(FileDesc *f) { (void)f; }
void Files__Close   (FileDesc *f) { (void)f; }
void Files__Purge   (FileDesc *f) { (void)f; }

void Files__Delete(const char *name, int name_len, int *res) {
    (void)name; (void)name_len; if (res) *res = 1;
}
void Files__Rename(const char *oldn, int old_len,
                   const char *newn, int new_len, int *res) {
    (void)oldn; (void)old_len; (void)newn; (void)new_len;
    if (res) *res = 1;
}
int Files__Length(FileDesc *f) { (void)f; return 0; }
int Files__Date  (FileDesc *f) { (void)f; return 0; }

void Files__Exists(const char *name, int name_len, int *res) {
    (void)name; (void)name_len; if (res) *res = 0;
}
void Files__MakeDir(const char *name, int name_len, int *res) {
    (void)name; (void)name_len; if (res) *res = 1;
}

void Files__Set (Rider *r, FileDesc *f, int pos) { (void)r; (void)f; (void)pos; }
int  Files__Pos (Rider *r) { (void)r; return 0; }
FileDesc *Files__Base(Rider *r) { (void)r; return 0; }

void Files__ReadByte  (Rider *r, int8_t *x)              { (void)r; if (x) *x = 0; }
void Files__ReadBytes (Rider *r, uint8_t *x, int xl, int n) { (void)r; (void)xl; (void)n;
                                                              for (int i=0;i<n;i++) x[i]=0; }
void Files__Read      (Rider *r, char *ch)              { (void)r; if (ch) *ch = 0; }
void Files__ReadInt   (Rider *r, int *x)                { (void)r; if (x) *x = 0; }
void Files__ReadString(Rider *r, char *out, int outlen) { (void)r; if (outlen>0) out[0]=0; }
void Files__ReadNum   (Rider *r, int *x)                { (void)r; if (x) *x = 0; }

void Files__WriteByte  (Rider *r, int8_t x)               { (void)r; (void)x; }
void Files__WriteBytes (Rider *r, const uint8_t *x, int xl, int n) {
    (void)r; (void)x; (void)xl; (void)n; }
void Files__Write      (Rider *r, char ch)                { (void)r; (void)ch; }
void Files__WriteInt   (Rider *r, int x)                  { (void)r; (void)x; }
void Files__WriteString(Rider *r, const char *s, int sl)  { (void)r; (void)s; (void)sl; }
void Files__WriteNum   (Rider *r, int x)                  { (void)r; (void)x; }

void Files__init(void) {}
