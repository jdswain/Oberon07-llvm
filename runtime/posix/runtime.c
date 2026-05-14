/* OC runtime: ARC-style reference counting allocator + helpers.
 *
 * Object layout (compiler-emitted):
 *   { ptr tag, i64 refcount, ...source-ordered fields }
 *
 * Type-descriptor layout (compiler-emitted):
 *   { i64 size, i32 ext_level, i32 _pad, [8 x ptr] ancestors,
 *     i32 ptr_offsets[]; -1 terminated }
 *
 * The compiler emits oc_retain on every pointer-store of an in-scope value,
 * oc_release on the displaced value, and oc_release on every local pointer
 * at scope exit. NEW initializes refcount to 0 and lets the surrounding
 * store call oc_retain — uniform with regular assignment.
 */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

/* Header offsets, in bytes, from the user pointer (which is what the
 * compiler-emitted code holds). */
#define OC_TAG_OFFSET   0
#define OC_RC_OFFSET    8

/* TD field offsets. Must match Ty_TDPrefix in src/ORG.c. */
#define TD_SIZE_OFFSET     0
#define TD_EXT_OFFSET      8
#define TD_ANCESTORS_OFF  16   /* 16 = 8(size) + 4(ext) + 4(pad) */
#define TD_LEVELS         8
#define TD_PTRS_OFFSET    (TD_ANCESTORS_OFF + TD_LEVELS * sizeof(void *))

static inline int64_t *oc_rc_slot(void *p) {
    return (int64_t *)((char *)p + OC_RC_OFFSET);
}
static inline void *oc_tag(void *p) {
    return *(void **)((char *)p + OC_TAG_OFFSET);
}
static inline int64_t oc_td_size(void *td) {
    return *(int64_t *)((char *)td + TD_SIZE_OFFSET);
}
static inline const int32_t *oc_td_ptr_offsets(void *td) {
    return (const int32_t *)((char *)td + TD_PTRS_OFFSET);
}

/* For diagnostics / leak-checking in tests. */
static int64_t oc_live = 0;
int64_t oc_live_objects(void) { return oc_live; }

/* Allocate a fresh object initialised to {tag, 0, all-zero-fields}. The
 * caller (compiler-emitted code) is responsible for the first oc_retain
 * — this matches the assignment convention. */
void *oc_alloc(void *td) {
    int64_t size = oc_td_size(td);
    void *p = calloc(1, (size_t)size);
    if (!p) return NULL;
    *(void **)((char *)p + OC_TAG_OFFSET) = td;
    /* refcount already zeroed by calloc */
    oc_live++;
    return p;
}

/* C-side stack/static records can mark themselves immortal by setting
 * _rc to any negative value. retain/release skip these — they never get
 * freed and the count never moves past the sentinel. Useful when handing
 * a non-heap pointer into Oberon code that does ARC bookkeeping. */
#define OC_IS_IMMORTAL(rc) ((rc) < 0)

void oc_retain(void *p) {
    if (!p) return;
    int64_t *rc = oc_rc_slot(p);
    if (OC_IS_IMMORTAL(*rc)) return;
    (*rc)++;
}

void oc_release(void *p) {
    if (!p) return;
    int64_t *rc = oc_rc_slot(p);
    if (OC_IS_IMMORTAL(*rc)) return;
    if (--(*rc) > 0) return;

    /* Drop refs on every pointer-typed field listed in the TD. */
    void *td = oc_tag(p);
    if (td) {
        const int32_t *off = oc_td_ptr_offsets(td);
        for (; *off != -1; off++) {
            void *child = *(void **)((char *)p + *off);
            oc_release(child);
        }
    }
    free(p);
    oc_live--;
}

/* Drop refs on every pointer-typed field of a stack-allocated (or otherwise
 * non-heap) record. Used by procedure epilogues to release child pointers
 * of local records without freeing the record itself. */
void oc_release_fields(void *p, void *td) {
    if (!p || !td) return;
    const int32_t *off = oc_td_ptr_offsets(td);
    for (; *off != -1; off++) {
        void *child = *(void **)((char *)p + *off);
        oc_release(child);
    }
}

/* Record-to-record assignment that maintains refcount balance.
 * Retains src's pointer fields, releases dst's, then copies the body.
 * The {tag, _rc} header is preserved on dst — copying it would clobber
 * the immortal sentinel of stack records and confuse heap records about
 * who owns them. */
void oc_record_assign(void *dst, void *src, void *td) {
    if (!dst || !src || !td) return;
    int64_t size = oc_td_size(td);

    const int32_t *off;
    /* Retain new before release old, in case dst==src. */
    for (off = oc_td_ptr_offsets(td); *off != -1; off++) {
        oc_retain(*(void **)((char *)src + *off));
    }
    for (off = oc_td_ptr_offsets(td); *off != -1; off++) {
        oc_release(*(void **)((char *)dst + *off));
    }

    if (size > 16) {
        memcpy((char *)dst + 16, (char *)src + 16, (size_t)(size - 16));
    }
}

/* Release every element of an ARRAY OF POINTER. Used by procedure epilogues
 * to clean up top-level pointer-array locals. */
void oc_release_array(void *p, int64_t n) {
    if (!p || n <= 0) return;
    void **arr = (void **)p;
    for (int64_t i = 0; i < n; i++) oc_release(arr[i]);
}

/* Same idea for an ARRAY of records-with-pointer-fields. */
void oc_release_array_fields(void *p, int64_t n, int64_t elem_size, void *elem_td) {
    if (!p || !elem_td || n <= 0) return;
    for (int64_t i = 0; i < n; i++) {
        oc_release_fields((char *)p + i * elem_size, elem_td);
    }
}

/* Process argv stash. The compiler-emitted entry stub calls oc_set_args
 * before invoking <Module>__init, so module bodies and any later code
 * can read argv via oc_argc / oc_argv. Argument strings stay owned by
 * the OS; we just keep the pointers. */
static int    oc_args_argc = 0;
static char **oc_args_argv = NULL;

void oc_set_args(int argc, char **argv) {
    oc_args_argc = argc;
    oc_args_argv = argv;
}

int oc_argc(void) {
    return oc_args_argc;
}

const char *oc_argv(int i) {
    if (i < 0 || i >= oc_args_argc || oc_args_argv == NULL) return "";
    return oc_args_argv[i];
}
