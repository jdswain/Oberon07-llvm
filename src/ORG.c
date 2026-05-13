/*
 * OC - Oberon Compiler (LLVM backend)
 * Copyright (C) 2024-2026 Jason Swain
 */

// ORG.c - LLVM-IR code generator for the Oberon front-end.
//
// State model:
//  - Each Oberon module compiles to one LLVMModule, written out as <modid>.ll.
//  - The module body (BEGIN .. END) becomes a function `<modid>__init` so the
//    eventual linker can call it once at program start.
//  - Locals/parameters become allocas in the function entry block; module-level
//    vars become LLVM global variables.
//  - ORG_Item carries either a constant (in `a`) or an LLVMValueRef of the
//    address (`backend`) for L-values, or an LLVMValueRef of the value itself
//    (`backend`) for already-loaded R-values (mode == Reg) and conditions
//    (mode == Cond).
//  - Forward branch fixup chains are mapped onto a label table holding LLVM
//    BasicBlocks. ORG_FJump emits a `br pending_bb` whose target gets its own
//    terminator filled in at ORG_FixLink time.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#include <llvm-c/Core.h>
#include <llvm-c/Analysis.h>
#include <llvm-c/BitWriter.h>
#include <llvm-c/Target.h>
#include <llvm-c/TargetMachine.h>

#include "ORG.h"
#include "ORS.h"
#include "ORB.h"

// --- Item modes beyond the ORB_class values ---
#define Reg  10  // value already in an SSA register; backend holds LLVMValueRef
#define RegI 11  // (unused) loaded indirect
#define Cond 12  // i1 condition value in `backend`

LONGINT ORG_pc = 0;
LONGINT ORG_varsize = 0;

static LLVMContextRef Ctx;
static LLVMModuleRef  Mod;
static LLVMBuilderRef Bld;
static LLVMValueRef   ModInit;        // <modid>__init function
static LLVMBasicBlockRef ModInitDoneBB;  // shared "ret void" block of ModInit
static LLVMValueRef   CurFn;          // function currently being emitted into
static char           ModName[128];

// Cached basic types
static LLVMTypeRef Ty_i1, Ty_i8, Ty_i32, Ty_i64, Ty_float, Ty_void, Ty_ptr;

// Type descriptor prefix. Every record's TD begins with this struct; the
// trailing ptr_offsets array (variable length) lives after. Used by the
// IS-test and (later) by oc_release to find pointer fields.
//
//   { i64 size, i32 ext_level, i32 _pad, [TD_LEVELS x ptr] ancestors }
static LLVMTypeRef Ty_TDPrefix;

// Cached target info — set once on first ORG_Open and reused for every
// emitted module. Triple/layout get stamped onto each module so the
// generated .ll is self-describing; HostTM is kept alive so ORG_Close can
// emit a native .o directly without shelling out to llc.
static char               *HostTriple = NULL;
static char               *HostLayout = NULL;
static LLVMTargetMachineRef HostTM    = NULL;

// Driver flags controlling what ORG_Close writes out. Defaults match the
// original behaviour (both files emitted).
static BOOLEAN EmitLL  = TRUE;
static BOOLEAN EmitObj = TRUE;

void ORG_SetEmitFlags(BOOLEAN emit_ll, BOOLEAN emit_obj) {
    EmitLL  = emit_ll;
    EmitObj = emit_obj;
}

// Forward branch label registry. Each entry is one LLVM BasicBlock that needs
// its terminator filled in later.
#define MAX_LABELS 4096
typedef struct {
    LLVMBasicBlockRef bb;
    int next;   // chain link, 0 = end
} Label;
static Label  Labels[MAX_LABELS];
static int    LabelCount;     // index 0 reserved as "no label"

// Pending-call argument stacks
#define MAX_CALL_DEPTH 32
#define MAX_CALL_ARGS  32
static LLVMValueRef CallArgs[MAX_CALL_DEPTH][MAX_CALL_ARGS];
static BOOLEAN      CallArgOwned[MAX_CALL_DEPTH][MAX_CALL_ARGS];
static int          CallArgC[MAX_CALL_DEPTH];
static int          CallTop;

// Pointer slots in the current function that the procedure prologue
// initialised to NIL or retained on entry. Their targets get released at
// scope exit so allocations don't leak when control leaves the procedure.
#define MAX_LOCAL_PTRS 64
static LLVMValueRef LocalPtrSlots[MAX_LOCAL_PTRS];
static int          NumLocalPtrs;

// Stack-allocated records that contain pointer fields. On scope exit we
// call oc_release_fields(slot, td) to release each child pointer without
// freeing the slot itself.
#define MAX_LOCAL_RECS 32
static LLVMValueRef LocalRecSlots[MAX_LOCAL_RECS];
static LLVMValueRef LocalRecTds  [MAX_LOCAL_RECS];
static int          NumLocalRecs;

// Stack-allocated ARRAY OF POINTER (or ARRAY OF record-with-ptr-fields).
// Each element gets released by oc_release_array / oc_release_array_fields
// on scope exit.
#define MAX_LOCAL_ARRS 16
typedef struct {
    LLVMValueRef slot;
    int32_t      len;
    LLVMValueRef elem_td;     // NULL for ARRAY OF POINTER, TD for ARRAY OF RECORD
    int32_t      elem_size;   // bytes per element
} LocalArrInfo;
static LocalArrInfo LocalArrs[MAX_LOCAL_ARRS];
static int          NumLocalArrs;

static void record_ptr_offsets(ORB_Type *t, int32_t base_off,
                               int32_t *out, int *count, int max);

// Returns true if a record type contains at least one pointer-typed cell
// (directly, or in nested records / fixed arrays).
static BOOLEAN record_has_ptr_fields(ORB_Type *t) {
    if (!t || t->form != ORB_Record) return FALSE;
    int32_t buf[64]; int n = 0;
    record_ptr_offsets(t, 0, buf, &n, 63);
    return n > 0;
}

// Counts user-visible statements emitted into the current function body
// (reset at ORG_Enter and after ORG_Header's import-init chain). If still
// zero at ORG_Return / ORG_Close and the procedure returns nothing, the
// function is a signature stub — we mark it weak so a C runtime's strong
// definition can override it without a link-time conflict. See discussion
// in commit message / chat for design notes.
static int EmittedStmts;

// --- helpers ---

static int new_label(LLVMBasicBlockRef bb, int next) {
    if (LabelCount + 1 >= MAX_LABELS) {
        ORS_Mark("label table overflow");
        return 0;
    }
    LabelCount++;
    Labels[LabelCount].bb = bb;
    Labels[LabelCount].next = next;
    return LabelCount;
}

static int current_block_terminated(void) {
    LLVMBasicBlockRef bb = LLVMGetInsertBlock(Bld);
    if (!bb) return 1;
    LLVMValueRef term = LLVMGetBasicBlockTerminator(bb);
    return term != NULL;
}

static LLVMBasicBlockRef append_block(const char *name) {
    LLVMValueRef fn = CurFn ? CurFn : ModInit;
    return LLVMAppendBasicBlockInContext(Ctx, fn, name);
}

static LLVMTypeRef LlvmType(ORB_Type *t);

// True iff this Oberon parameter expands into 2 LLVM args (ptr + length).
static BOOLEAN is_open_array(ORB_Object *p) {
    return p && p->type && p->type->form == ORB_Array && p->type->len < 0;
}

// LLVM function type for an Oberon procedure type. Open-array parameters
// expand to two LLVM args: ptr and i32 length.
static LLVMTypeRef ProcType(ORB_Type *pt) {
    int n = pt->nofpar;
    int n_llvm = 0;
    ORB_Object *p = pt->dsc;
    int i = 0;
    while (p && i < n) {
        n_llvm += is_open_array(p) ? 2 : 1;
        i++; p = p->next;
    }
    LLVMTypeRef params_buf[64];
    LLVMTypeRef *params = (n_llvm > 64)
        ? malloc(sizeof(LLVMTypeRef) * (n_llvm > 0 ? n_llvm : 1))
        : params_buf;
    int j = 0;
    p = pt->dsc;
    i = 0;
    while (p && i < n) {
        if (is_open_array(p)) {
            params[j++] = Ty_ptr;     // data pointer
            params[j++] = Ty_i32;     // length
        } else if (p->class == ORB_Par) {
            params[j++] = Ty_ptr;     // VAR / promoted-struct
        } else {
            params[j++] = LlvmType(p->type);
        }
        i++; p = p->next;
    }
    LLVMTypeRef ret = LlvmType(pt->base);
    LLVMTypeRef ft = LLVMFunctionType(ret, params, n_llvm, 0);
    if (params != params_buf) free(params);
    return ft;
}

static LLVMTypeRef LlvmType(ORB_Type *t) {
    if (!t) return Ty_void;
    if (t->backend) return (LLVMTypeRef)t->backend;
    LLVMTypeRef ty = NULL;
    switch (t->form) {
        case ORB_Bool:   ty = Ty_i1;    break;
        case ORB_Byte:   ty = Ty_i8;    break;
        case ORB_Char:   ty = Ty_i8;    break;
        case ORB_Int:
            if      (t->size <= 1) ty = Ty_i8;
            else if (t->size <= 4) ty = Ty_i32;
            else                   ty = Ty_i64;
            break;
        case ORB_Real:   ty = Ty_float; break;
        case ORB_Set:    ty = Ty_i32;   break;
        case ORB_NilTyp: ty = Ty_ptr;   break;
        case ORB_Pointer:ty = Ty_ptr;   break;
        case ORB_Proc:   ty = Ty_ptr;   break;
        case ORB_NoTyp:  ty = Ty_void;  break;
        case ORB_String: ty = Ty_ptr;   break;
        case ORB_Array: {
            unsigned len = t->len > 0 ? (unsigned)t->len : 0;
            ty = LLVMArrayType2(LlvmType(t->base), len);
            break;
        }
        case ORB_Record: {
            // LLVM layout: { tag: ptr, refcount: i64, ...source-ordered fields }
            //
            // tag      — pointer to type descriptor (used by IS-test / oc_release)
            // refcount — ARC strong-count; managed by oc_retain / oc_release
            //
            // Fields in `t->dsc` are stored reverse-source-order (parser
            // prepends each declaration), so we fill the LLVM struct backwards.
            // For records with extensions, t->dsc already includes parent
            // fields after the new ones, giving the full
            // {parent-fields..., own-fields...} layout in source order.
            int nf = 0;
            for (ORB_Object *f = t->dsc; f; f = f->next) nf++;
            int total = 2 + nf;
            LLVMTypeRef tmp[64];
            LLVMTypeRef *fts = (total > 64) ? malloc(sizeof(LLVMTypeRef) * total) : tmp;
            fts[0] = Ty_ptr;        // tag
            fts[1] = Ty_i64;        // refcount
            int i = nf + 1;
            for (ORB_Object *f = t->dsc; f; f = f->next) fts[i--] = LlvmType(f->type);
            ty = LLVMStructTypeInContext(Ctx, fts, total, 0);
            if (fts != tmp) free(fts);
            break;
        }
        default: ty = Ty_void; break;
    }
    t->backend = ty;
    return ty;
}

// For an imported object (lev < 0), find the originating module's name.
// Walks the active scope chain looking for an ORB_Mod with matching index.
static const char *find_module_name(ORB_Object *obj) {
    if (obj->lev >= 0) return ModName;
    int target = -obj->lev;
    if (target == 0) return ModName;
    ObjectPtr scope = topScope;
    while (scope) {
        for (ObjectPtr o = scope->next; o; o = o->next) {
            if (o->class == ORB_Mod && o->lev == target) {
                return ((ModulePtr)o)->orgname;
            }
        }
        scope = scope->dsc;
    }
    return ModName;
}

// Lazily declare an LLVM function for an Oberon procedure. Imported procs get
// their owning module's prefix and stay external (no body); local procs get
// our module's prefix and pick up internal/external linkage in ORG_Enter.
static LLVMValueRef LookupProc(ORB_Object *proc) {
    if (proc->backend) return (LLVMValueRef)proc->backend;
    LLVMTypeRef ft = ProcType(proc->type);
    char qname[200];
    snprintf(qname, sizeof(qname), "%s__%s", find_module_name(proc), proc->name);
    // Reuse an existing extern declaration if one was already created (e.g.
    // by ORG_Header for an imported module's init function).
    LLVMValueRef fn = LLVMGetNamedFunction(Mod, qname);
    if (!fn) fn = LLVMAddFunction(Mod, qname, ft);
    proc->backend = fn;
    return fn;
}

// --- Type descriptors (RTTI) ---
//
// Each record type has a type descriptor (TD) that's a private global of
// LLVM type [TD_LEVELS x ptr]. Slot i contains the TD of the ancestor at
// extension level i; slot t->nofpar is the type's own TD; slots beyond are
// NULL. NEW initializes a record's tag (struct field 0) to its TD pointer.
//
// `x IS T` becomes:  load tag(x); load tag[T.nofpar]; icmp eq, T.td.
//
// This handles inheritance with a single load+compare. Limit of TD_LEVELS
// caps the inheritance depth — 8 is plenty for typical Oberon programs.

#define TD_LEVELS 8

static ORB_Type *type_at_level(ORB_Type *t, int level) {
    while (t && t->nofpar > level) t = t->base;
    return t;
}

// Convert an LLVM struct field index to its byte offset (using HostTM data
// layout). Returns 0 if no target machine is available (shouldn't happen
// once ORG_Open has run).
static uint64_t struct_field_offset(LLVMTypeRef rec_ty, unsigned field_idx) {
    if (!HostTM) return 0;
    LLVMTargetDataRef dl = LLVMCreateTargetDataLayout(HostTM);
    uint64_t off = LLVMOffsetOfElement(dl, rec_ty, field_idx);
    LLVMDisposeTargetData(dl);
    return off;
}

// Walk a record's pointer-typed fields and append their byte offsets to
// `out` (with respect to the record's base — i.e., the user pointer, after
// the {tag, refcount} header). Recurses into nested records and expands
// fixed-size arrays element-wise.
static void record_ptr_offsets(ORB_Type *t, int32_t base_off,
                                int32_t *out, int *count, int max) {
    if (!t || t->form != ORB_Record || *count >= max) return;
    LLVMTypeRef rec_ty = LlvmType(t);
    int nf = 0;
    for (ORB_Object *f = t->dsc; f; f = f->next) nf++;
    // Field LLVM indices: 2..(2+nf-1). dsc head = highest LLVM index (last
    // declared field); dsc tail = lowest LLVM index (first declared).
    int llvm_idx = 1 + nf;
    for (ORB_Object *f = t->dsc; f; f = f->next) {
        uint64_t field_off = struct_field_offset(rec_ty, (unsigned)llvm_idx);
        int32_t total_off = base_off + (int32_t)field_off;
        if (f->type) {
            // WEAK pointer fields are deliberately omitted from ptr_offsets:
            // oc_release_fields shouldn't release them when the parent is
            // freed (that's what makes them cycle-breakers).
            if (f->type->form == ORB_Pointer && !f->type->weak && *count < max) {
                out[(*count)++] = total_off;
            } else if (f->type->form == ORB_Record) {
                record_ptr_offsets(f->type, total_off, out, count, max);
            } else if (f->type->form == ORB_Array && f->type->len > 0) {
                ORB_Type *elt = f->type->base;
                LLVMTypeRef elt_lt = LlvmType(elt);
                LLVMTargetDataRef dl = HostTM ? LLVMCreateTargetDataLayout(HostTM) : NULL;
                uint64_t elt_sz = dl ? LLVMABISizeOfType(dl, elt_lt) : 0;
                if (dl) LLVMDisposeTargetData(dl);
                for (int32_t k = 0; k < f->type->len && *count < max; k++) {
                    int32_t e_off = total_off + (int32_t)(k * elt_sz);
                    if (elt && elt->form == ORB_Pointer && !elt->weak) {
                        out[(*count)++] = e_off;
                    } else if (elt && elt->form == ORB_Record) {
                        record_ptr_offsets(elt, e_off, out, count, max);
                    }
                }
            }
        }
        llvm_idx--;
    }
}

static LLVMValueRef record_td(ORB_Type *t) {
    if (!t || t->form != ORB_Record) return LLVMConstNull(Ty_ptr);
    if (t->backend2) return (LLVMValueRef)t->backend2;

    int self_level = t->nofpar;

    // Forward-declare the global so self-references resolve. Use the
    // concrete struct type once we know the ptr_offsets length.
    char tdname[256];
    const char *tn = (t->typobj && t->typobj->name[0]) ? t->typobj->name : "anon";
    snprintf(tdname, sizeof(tdname), "%s__%s__td", ModName, tn);

    // Collect ptr offsets. base_off=0 means "relative to the user pointer"
    // — oc_release receives the user pointer (after the {tag,refcount}
    // header), so offsets here directly index into the record body.
    int32_t offsets[64];
    int n_off = 0;
    record_ptr_offsets(t, 0, offsets, &n_off, 63);
    offsets[n_off++] = -1;   // terminator

    LLVMTypeRef ancestors_ty = LLVMArrayType2(Ty_ptr, TD_LEVELS);
    LLVMTypeRef tail_ty = LLVMArrayType2(Ty_i32, n_off);
    LLVMTypeRef td_field_ty[] = {
        Ty_i64, Ty_i32, Ty_i32, ancestors_ty, tail_ty,
    };
    LLVMTypeRef td_ty = LLVMStructTypeInContext(Ctx, td_field_ty, 5, 0);

    LLVMValueRef td = LLVMAddGlobal(Mod, td_ty, tdname);
    LLVMSetLinkage(td, LLVMInternalLinkage);
    LLVMSetGlobalConstant(td, 1);
    t->backend2 = td;   // cache before recursing on ancestors

    // Build ancestors after caching `td` so self-reference works.
    LLVMValueRef anc_vals[TD_LEVELS];
    for (int level = 0; level < TD_LEVELS; level++) {
        if (level > self_level) {
            anc_vals[level] = LLVMConstNull(Ty_ptr);
        } else {
            ORB_Type *anc = type_at_level(t, level);
            anc_vals[level] = (anc == t) ? td : record_td(anc);
        }
    }

    LLVMValueRef offset_consts[64];
    for (int i = 0; i < n_off; i++) {
        offset_consts[i] = LLVMConstInt(Ty_i32, (uint64_t)(int64_t)offsets[i], 1);
    }

    LLVMTypeRef record_lt = LlvmType(t);
    LLVMValueRef size_val = LLVMSizeOf(record_lt);

    LLVMValueRef init_fields[5] = {
        size_val,
        LLVMConstInt(Ty_i32, (uint64_t)self_level, 0),
        LLVMConstInt(Ty_i32, 0, 0),
        LLVMConstArray2(Ty_ptr, anc_vals, TD_LEVELS),
        LLVMConstArray2(Ty_i32, offset_consts, n_off),
    };
    LLVMValueRef init = LLVMConstNamedStruct(td_ty, init_fields, 5);
    LLVMSetInitializer(td, init);
    return td;
}

// --- ARC retain/release helpers ---
//
// emit_retain(v) and emit_release(v) generate a call to the runtime
// helpers, which are no-ops when v is NIL. We declare them lazily in the
// current module so multiple calls share one declaration.
static LLVMValueRef arc_helper(const char *name) {
    LLVMValueRef fn = LLVMGetNamedFunction(Mod, name);
    if (!fn) {
        LLVMTypeRef pt[1] = { Ty_ptr };
        LLVMTypeRef ft = LLVMFunctionType(Ty_void, pt, 1, 0);
        fn = LLVMAddFunction(Mod, name, ft);
    }
    return fn;
}

static void emit_retain(LLVMValueRef v) {
    if (!v) return;
    LLVMValueRef fn = arc_helper("oc_retain");
    LLVMTypeRef pt[1] = { Ty_ptr };
    LLVMTypeRef ft = LLVMFunctionType(Ty_void, pt, 1, 0);
    LLVMValueRef args[1] = { v };
    LLVMBuildCall2(Bld, ft, fn, args, 1, "");
}

static void emit_release(LLVMValueRef v) {
    if (!v) return;
    LLVMValueRef fn = arc_helper("oc_release");
    LLVMTypeRef pt[1] = { Ty_ptr };
    LLVMTypeRef ft = LLVMFunctionType(Ty_void, pt, 1, 0);
    LLVMValueRef args[1] = { v };
    LLVMBuildCall2(Bld, ft, fn, args, 1, "");
}

// True iff a Type holds an ARC-managed pointer — i.e. a regular (strong)
// pointer. WEAK POINTER types are excluded: ARC skips retain/release on
// them and oc_release_fields ignores them, so they break reference cycles.
static BOOLEAN type_is_managed(ORB_Type *t) {
    return t && t->form == ORB_Pointer && !t->weak;
}

// Release the +1 reference an Item carries when its function-call origin
// is being consumed in a non-store context (relation, type test, parameter
// pass). After the release the item's `b` flag is cleared so the same
// reference isn't dropped twice if the value flows further.
static void consume_arc(ORG_Item *x, LLVMValueRef val) {
    if (x && x->mode == Reg && x->b == 1 && type_is_managed(x->type)) {
        emit_release(val);
        x->b = 0;
    }
}

// Widen the narrower of two integer values to match the wider, sign-
// extending. If x got widened, promote x->type to y's type so that the
// surrounding expression sees the wider Oberon type. Used by all integer
// arithmetic / comparison ops to handle mixed INTEGER+LONGINT operands.
static void coerce_pair(ORG_Item *x, ORG_Item *y,
                        LLVMValueRef *a, LLVMValueRef *b) {
    LLVMTypeRef at = LLVMTypeOf(*a), bt = LLVMTypeOf(*b);
    if (at == bt) return;
    if (LLVMGetTypeKind(at) != LLVMIntegerTypeKind ||
        LLVMGetTypeKind(bt) != LLVMIntegerTypeKind) return;
    unsigned aw = LLVMGetIntTypeWidth(at);
    unsigned bw = LLVMGetIntTypeWidth(bt);
    if (aw < bw) {
        *a = LLVMBuildSExt(Bld, *a, bt, "wid");
        x->type = y->type;
        x->orig_type = y->orig_type;
    } else {
        *b = LLVMBuildSExt(Bld, *b, at, "wid");
    }
}

// Constant integer of the given Oberon type.
static LLVMValueRef ConstOfType(ORB_Type *typ, LONGINT v) {
    LLVMTypeRef ty = LlvmType(typ);
    if (ty == Ty_float) {
        union { int32_t i; float f; } u; u.i = (int32_t)v;
        return LLVMConstReal(Ty_float, u.f);
    }
    if (ty == Ty_ptr) {
        return LLVMConstNull(Ty_ptr);
    }
    return LLVMConstInt(ty, (uint64_t)(int64_t)v, 1);
}

// Get x as an LLVM Value (loading from memory if needed).
static LLVMValueRef LoadItem(ORG_Item *x) {
    if (x->mode == ORB_Const) {
        // Procedure constants carry their LLVM function pointer in
        // x->backend (set by ORG_MakeItem via LookupProc). The generic
        // ConstOfType path collapses any pointer type to NULL, which
        // turns `procVar := someProc` and `Call(someProc)` into NIL
        // stores. Short-circuit to the function address when available.
        if (x->type && x->type->form == ORB_Proc && x->backend) {
            return (LLVMValueRef)x->backend;
        }
        return ConstOfType(x->type, x->a);
    }
    if (x->mode == Reg || x->mode == Cond) {
        return (LLVMValueRef)x->backend;
    }
    if ((x->mode == ORB_Var) || (x->mode == ORB_Par) ||
        (x->mode == ORB_Fld) || (x->mode == RegI)) {
        if (!x->backend) {
            // Should not happen — flag for visibility.
            ORS_Mark("internal: var item without backend");
            return LLVMConstInt(Ty_i32, 0, 0);
        }
        LLVMTypeRef ty = LlvmType(x->type);
        return LLVMBuildLoad2(Bld, ty, (LLVMValueRef)x->backend, "ld");
    }
    return LLVMConstInt(Ty_i32, 0, 0);
}

// Get x as an L-value (pointer to its memory).
static LLVMValueRef LValueItem(ORG_Item *x) {
    if (!x->backend) {
        ORS_Mark("internal: not an L-value");
        return LLVMConstNull(Ty_ptr);
    }
    return (LLVMValueRef)x->backend;
}

// --- Item construction ---

void ORG_MakeConstItem(ORG_Item *x, ORB_Type *typ, LONGINT val) {
    x->mode = ORB_Const;
    x->type = typ;
    x->a = val; x->b = 0; x->r = 0;
    x->rdo = FALSE;
    x->orig_type = typ;
    x->backend = NULL;
    x->backend2 = NULL;
}

void ORG_MakeRealItem(ORG_Item *x, REAL val) {
    union { REAL r; int32_t i; } u; u.r = val;
    x->mode = ORB_Const;
    x->type = realType;
    x->a = u.i; x->b = 0; x->r = 0;
    x->rdo = FALSE;
    x->orig_type = realType;
    x->backend = NULL;
    x->backend2 = NULL;
}

void ORG_MakeStringItem(ORG_Item *x, LONGINT len) {
    x->mode = ORB_Const;
    x->type = strType;
    // x->a holds the first byte so `s := "x"` (one-char string → CHAR) folds
    // into a constant store via ORG_StrToChar without a load.
    x->a = (len > 0) ? (uint8_t)ORS_str[0] : 0;
    x->b = len;
    x->r = 0;
    x->rdo = TRUE;
    x->orig_type = strType;
    x->backend = NULL;
    x->backend2 = NULL;
    // Materialize the literal in the module so StringParam / CopyString /
    // StringRelation can take its address. ORS_str already contains the
    // trailing 0X, and ORS_slen counts it, so we pass DontNullTerminate=1.
    if (Mod && Ctx && len > 0) {
        LLVMValueRef str_const = LLVMConstStringInContext(Ctx, ORS_str, (unsigned)len, 1);
        LLVMTypeRef arr_ty = LLVMArrayType2(Ty_i8, (unsigned)len);
        LLVMValueRef g = LLVMAddGlobal(Mod, arr_ty, ".str");
        LLVMSetInitializer(g, str_const);
        LLVMSetLinkage(g, LLVMPrivateLinkage);
        LLVMSetGlobalConstant(g, 1);
        x->backend = g;
    }
}

void ORG_MakeDataItem(ORG_Item *x, ORB_Type *typ, LONGINT offset, LONGINT size) {
    (void)size;
    x->mode = ORB_Var;
    x->type = typ;
    x->a = offset; x->b = 0; x->r = 0;
    x->rdo = TRUE;
    x->orig_type = typ;
    x->backend = NULL;
    x->backend2 = NULL;
}

LONGINT ORG_StrOffset(void) { return 0; }
void ORG_PutByte(int b) { (void)b; }

// Creates (or finds existing) global LLVM variable for an Oberon module-level
// variable. For imported variables, the module prefix is the owning module's
// orgname and the global has external linkage with no initializer.
static LLVMValueRef ensure_global(ORB_Object *obj) {
    if (obj->backend) return (LLVMValueRef)obj->backend;
    char qname[200];
    BOOLEAN imported = obj->lev < 0;
    snprintf(qname, sizeof(qname), "%s__%s", find_module_name(obj), obj->name);
    LLVMValueRef g = LLVMGetNamedGlobal(Mod, qname);
    if (!g) {
        LLVMTypeRef ty = LlvmType(obj->type);
        g = LLVMAddGlobal(Mod, ty, qname);
        if (imported) {
            // External — defined in the importing module's translation unit.
            LLVMSetLinkage(g, LLVMExternalLinkage);
        } else {
            LLVMSetInitializer(g, LLVMConstNull(ty));
            LLVMSetLinkage(g, obj->expo ? LLVMExternalLinkage : LLVMInternalLinkage);
        }
    }
    obj->backend = g;
    return g;
}

void ORG_MakeItem(ORG_Item *x, ORB_Object *y, LONGINT curlev) {
    (void)curlev;
    x->mode = y->class;
    x->type = y->type;
    x->a = y->val;
    x->b = 0;
    x->r = 0;
    x->rdo = y->rdo;
    x->orig_type = y->type;
    x->backend = NULL;
    x->backend2 = NULL;

    if (y->class == ORB_Var) {
        // lev == 0: this module's global; lev < 0: imported global (extern).
        // lev > 0: a procedure local (alloca set up in ORG_Enter).
        if (y->lev <= 0) {
            x->backend = ensure_global(y);
        } else {
            x->backend = y->backend;
        }
    } else if (y->class == ORB_Par) {
        // Param slot stores a pointer to the data (VAR / promoted struct).
        // Load it once so x->backend is the address of the actual data.
        // For open-array params we also load the cached length into backend2.
        if (y->backend) {
            x->backend = LLVMBuildLoad2(Bld, Ty_ptr, y->backend, y->name);
        }
        if (is_open_array(y) && y->backend2) {
            x->backend2 = LLVMBuildLoad2(Bld, Ty_i32, y->backend2, "len");
        }
    } else if (y->class == ORB_Const && y->type && y->type->form == ORB_Proc) {
        x->backend = LookupProc(y);
    }
}

// --- Selectors ---

// NOTE on type mutation: the parser updates x->type itself after each
// selector operation (e.g. `x->type = x->type->base;` after Index). These
// backends therefore must NOT mutate x->type — only x->backend.
void ORG_Field(ORG_Item *x, ORB_Object *y) {
    LLVMTypeRef rec_ty = LlvmType(x->type);
    if (!x->backend) {
        ORS_Mark("internal: ORG_Field with no backend");
        return;
    }
    // Find y's reverse-index in dsc (we built the LLVM struct reversed).
    int total = 0, pos = -1, i = 0;
    for (ORB_Object *f = x->type->dsc; f; f = f->next) {
        if (f == y) pos = i;
        i++;
    }
    total = i;
    // +2 skips the tag (LLVM index 0) and refcount (LLVM index 1).
    unsigned idx = (pos >= 0) ? (unsigned)(2 + total - 1 - pos) : 2u;
    x->backend = LLVMBuildStructGEP2(Bld, rec_ty,
        (LLVMValueRef)x->backend, idx, y->name);
}

void ORG_Index(ORG_Item *x, ORG_Item *y) {
    if (!x->backend) {
        ORS_Mark("internal: ORG_Index with no backend");
        return;
    }
    LLVMValueRef idx = LoadItem(y);
    LLVMTypeRef it = LLVMTypeOf(idx);
    if (it != Ty_i32 && LLVMGetTypeKind(it) == LLVMIntegerTypeKind) {
        unsigned w = LLVMGetIntTypeWidth(it);
        if (w < 32) idx = LLVMBuildSExt(Bld, idx, Ty_i32, "ix");
        else if (w > 32) idx = LLVMBuildTrunc(Bld, idx, Ty_i32, "ix");
    }
    if (x->type->len < 0) {
        // Open array — backend is a raw element pointer; use 1-index GEP.
        LLVMTypeRef elt_ty = LlvmType(x->type->base);
        x->backend = LLVMBuildGEP2(Bld, elt_ty,
            (LLVMValueRef)x->backend, &idx, 1, "el");
    } else {
        // Fixed-size array — backend is a [N x T] pointer; use 2-index GEP.
        LLVMTypeRef arr_ty = LlvmType(x->type);
        LLVMValueRef indices[2] = { LLVMConstInt(Ty_i32, 0, 0), idx };
        x->backend = LLVMBuildGEP2(Bld, arr_ty,
            (LLVMValueRef)x->backend, indices, 2, "el");
    }
}

void ORG_DeRef(ORG_Item *x) {
    if (x->backend) {
        x->backend = LLVMBuildLoad2(Bld, Ty_ptr, (LLVMValueRef)x->backend, "deref");
    }
}

// --- Type metadata / type tests ---
void ORG_BuildTD(ORB_Type *T, LONGINT *dc) { (void)T; (void)dc; }
void ORG_TypeTest(ORG_Item *x, ORB_Type *T, BOOLEAN varpar, BOOLEAN isguard) {
    (void)varpar;
    // The parser signals "trivially true" by passing T=NULL — this happens
    // when the IS test's RHS is the static type of the LHS or one of its
    // ancestors (the dynamic type is always at least that deep).
    if (!T) {
        if (!isguard) {
            x->mode = Cond;
            x->type = boolType;
            x->backend = LLVMConstInt(Ty_i1, 1, 0);
        }
        return;
    }

    // Locate the record start (offset 0 holds the tag).
    LLVMValueRef rec_ptr;
    ORB_Type *rec_type;
    if (x->type && x->type->form == ORB_Pointer) {
        rec_ptr = LLVMBuildLoad2(Bld, Ty_ptr, LValueItem(x), "rec");
        rec_type = x->type->base;
    } else {
        rec_ptr = (LLVMValueRef)x->backend;
        rec_type = x->type;
    }
    if (!rec_ptr || !rec_type) {
        if (!isguard) {
            x->mode = Cond;
            x->type = boolType;
            x->backend = LLVMConstInt(Ty_i1, 0, 0);
        }
        return;
    }

    // Load the tag.
    LLVMTypeRef rec_lt = LlvmType(rec_type);
    LLVMValueRef tag_slot = LLVMBuildStructGEP2(Bld, rec_lt, rec_ptr, 0, "tag_slot");
    LLVMValueRef tag = LLVMBuildLoad2(Bld, Ty_ptr, tag_slot, "tag");

    // T may itself be a pointer; the actual record is its base.
    ORB_Type *target_record = (T->form == ORB_Pointer) ? T->base : T;
    LLVMValueRef target_td = record_td(target_record);
    int level = target_record ? target_record->nofpar : 0;
    if (level >= TD_LEVELS) level = TD_LEVELS - 1;

    // anc = tag.ancestors[level]   (TD layout: { i64, i32, i32, [N x ptr], ... })
    LLVMValueRef indices[3] = {
        LLVMConstInt(Ty_i32, 0, 0),
        LLVMConstInt(Ty_i32, 3, 0),                       // ancestors field
        LLVMConstInt(Ty_i32, (uint64_t)level, 0)
    };
    LLVMValueRef anc_slot = LLVMBuildGEP2(Bld, Ty_TDPrefix, tag, indices, 3, "anc_slot");
    LLVMValueRef anc = LLVMBuildLoad2(Bld, Ty_ptr, anc_slot, "anc");
    LLVMValueRef cond = LLVMBuildICmp(Bld, LLVMIntEQ, anc, target_td, "is");

    // Consume +1 ownership if x came from a function-call result.
    consume_arc(x, rec_ptr);

    if (!isguard) {
        x->mode = Cond;
        x->type = boolType;
        x->backend = cond;
        x->b = 0;
        x->backend2 = NULL;
    }
    // For type-guards (WITH / type-CASE), the parser updates x->type itself.
    // A real implementation would also assert the test passes; skip for now.
}

// --- Boolean ---
void ORG_Not(ORG_Item *x) {
    LLVMValueRef v = LoadItem(x);
    if (LLVMTypeOf(v) != Ty_i1) {
        v = LLVMBuildICmp(Bld, LLVMIntNE, v, LLVMConstInt(LLVMTypeOf(v), 0, 0), "tobool");
    }
    x->mode = Cond;
    x->type = boolType;
    x->backend = LLVMBuildNot(Bld, v, "not");
}

// Short-circuit AND.
//
// Parser sequence for `x & y`:
//   And1(x); factor(y); And2(x, y);
//
// LLVM lowering:
//   and1:                           ; predecessor
//     %cx = ...x...
//     br i1 %cx, label %and_cont, label %and_skip
//   and_cont:                       ; only reached if cx was true
//     %cy = ...y...
//     br label %and_merge
//   and_skip:                       ; cx was false
//     br label %and_merge
//   and_merge:
//     %r = phi i1 [ %cy, %and_cont_end ], [ false, %and_skip ]
//
// We stash the skip BB in x->backend2 between And1 and And2.
void ORG_And1(ORG_Item *x) {
    LLVMValueRef cond = LoadItem(x);
    if (LLVMTypeOf(cond) != Ty_i1) {
        cond = LLVMBuildICmp(Bld, LLVMIntNE, cond, LLVMConstInt(LLVMTypeOf(cond), 0, 0), "tobool");
    }
    LLVMBasicBlockRef cont = append_block("and_cont");
    LLVMBasicBlockRef skip = append_block("and_skip");
    LLVMBuildCondBr(Bld, cond, cont, skip);
    LLVMPositionBuilderAtEnd(Bld, cont);
    x->mode = Cond;
    x->type = boolType;
    x->backend = NULL;
    x->backend2 = (void*)skip;
}

void ORG_And2(ORG_Item *x, ORG_Item *y) {
    LLVMBasicBlockRef skip = (LLVMBasicBlockRef)x->backend2;
    if (!skip) {
        // No And1 was called — fall back to eager AND.
        LLVMValueRef a = LoadItem(x), b = LoadItem(y);
        x->mode = Cond;
        x->type = boolType;
        x->backend = LLVMBuildAnd(Bld, a, b, "and");
        x->backend2 = NULL;
        return;
    }
    LLVMValueRef cy = LoadItem(y);
    if (LLVMTypeOf(cy) != Ty_i1) {
        cy = LLVMBuildICmp(Bld, LLVMIntNE, cy, LLVMConstInt(LLVMTypeOf(cy), 0, 0), "tobool");
    }
    LLVMBasicBlockRef from_cont = LLVMGetInsertBlock(Bld);
    LLVMBasicBlockRef merge = append_block("and_merge");
    LLVMBuildBr(Bld, merge);
    LLVMPositionBuilderAtEnd(Bld, skip);
    LLVMBuildBr(Bld, merge);
    LLVMPositionBuilderAtEnd(Bld, merge);
    LLVMValueRef phi = LLVMBuildPhi(Bld, Ty_i1, "and");
    LLVMValueRef incoming_vals[2] = { cy, LLVMConstInt(Ty_i1, 0, 0) };
    LLVMBasicBlockRef incoming_bbs[2] = { from_cont, skip };
    LLVMAddIncoming(phi, incoming_vals, incoming_bbs, 2);
    x->mode = Cond;
    x->type = boolType;
    x->backend = phi;
    x->backend2 = NULL;
}

// Short-circuit OR — mirrors AND with polarity flipped.
void ORG_Or1(ORG_Item *x) {
    LLVMValueRef cond = LoadItem(x);
    if (LLVMTypeOf(cond) != Ty_i1) {
        cond = LLVMBuildICmp(Bld, LLVMIntNE, cond, LLVMConstInt(LLVMTypeOf(cond), 0, 0), "tobool");
    }
    LLVMBasicBlockRef cont = append_block("or_cont");
    LLVMBasicBlockRef skip = append_block("or_skip");
    // If cond is true, take the short-circuit (skip). Otherwise evaluate y.
    LLVMBuildCondBr(Bld, cond, skip, cont);
    LLVMPositionBuilderAtEnd(Bld, cont);
    x->mode = Cond;
    x->type = boolType;
    x->backend = NULL;
    x->backend2 = (void*)skip;
}

void ORG_Or2(ORG_Item *x, ORG_Item *y) {
    LLVMBasicBlockRef skip = (LLVMBasicBlockRef)x->backend2;
    if (!skip) {
        LLVMValueRef a = LoadItem(x), b = LoadItem(y);
        x->mode = Cond;
        x->type = boolType;
        x->backend = LLVMBuildOr(Bld, a, b, "or");
        x->backend2 = NULL;
        return;
    }
    LLVMValueRef cy = LoadItem(y);
    if (LLVMTypeOf(cy) != Ty_i1) {
        cy = LLVMBuildICmp(Bld, LLVMIntNE, cy, LLVMConstInt(LLVMTypeOf(cy), 0, 0), "tobool");
    }
    LLVMBasicBlockRef from_cont = LLVMGetInsertBlock(Bld);
    LLVMBasicBlockRef merge = append_block("or_merge");
    LLVMBuildBr(Bld, merge);
    LLVMPositionBuilderAtEnd(Bld, skip);
    LLVMBuildBr(Bld, merge);
    LLVMPositionBuilderAtEnd(Bld, merge);
    LLVMValueRef phi = LLVMBuildPhi(Bld, Ty_i1, "or");
    LLVMValueRef incoming_vals[2] = { cy, LLVMConstInt(Ty_i1, 1, 0) };
    LLVMBasicBlockRef incoming_bbs[2] = { from_cont, skip };
    LLVMAddIncoming(phi, incoming_vals, incoming_bbs, 2);
    x->mode = Cond;
    x->type = boolType;
    x->backend = phi;
    x->backend2 = NULL;
}

// --- Arithmetic ---
void ORG_Neg(ORG_Item *x) {
    if (x->mode == ORB_Const && x->type && x->type->form == ORB_Int) {
        x->a = -x->a;
        return;
    }
    if (x->mode == ORB_Const && x->type && x->type->form == ORB_Set) {
        x->a = ~x->a;
        return;
    }
    LLVMValueRef v = LoadItem(x);
    x->mode = Reg;
    if (x->type && x->type->form == ORB_Real) {
        x->backend = LLVMBuildFNeg(Bld, v, "fneg");
    } else if (x->type && x->type->form == ORB_Set) {
        x->backend = LLVMBuildNot(Bld, v, "snot");
    } else {
        x->backend = LLVMBuildNeg(Bld, v, "neg");
    }
}

void ORG_AddOp(LONGINT op, ORG_Item *x, ORG_Item *y) {
    LLVMValueRef a = LoadItem(x), b = LoadItem(y);
    coerce_pair(x, y, &a, &b);
    LLVMValueRef r;
    if (op == ORS_plus) {
        r = LLVMBuildAdd(Bld, a, b, "add");
    } else { // ORS_minus
        r = LLVMBuildSub(Bld, a, b, "sub");
    }
    x->mode = Reg;
    x->backend = r;
}

void ORG_MulOp(ORG_Item *x, ORG_Item *y) {
    LLVMValueRef a = LoadItem(x), b = LoadItem(y);
    coerce_pair(x, y, &a, &b);
    x->mode = Reg;
    x->backend = LLVMBuildMul(Bld, a, b, "mul");
}

void ORG_DivOp(LONGINT op, ORG_Item *x, ORG_Item *y) {
    LLVMValueRef a = LoadItem(x), b = LoadItem(y);
    coerce_pair(x, y, &a, &b);
    x->mode = Reg;
    if (op == ORS_div) x->backend = LLVMBuildSDiv(Bld, a, b, "div");
    else               x->backend = LLVMBuildSRem(Bld, a, b, "mod");
}

void ORG_RealOp(INTEGER op, ORG_Item *x, ORG_Item *y) {
    LLVMValueRef a = LoadItem(x), b = LoadItem(y);
    LLVMValueRef r;
    if (op == ORS_plus)        r = LLVMBuildFAdd(Bld, a, b, "fadd");
    else if (op == ORS_minus)  r = LLVMBuildFSub(Bld, a, b, "fsub");
    else if (op == ORS_times)  r = LLVMBuildFMul(Bld, a, b, "fmul");
    else                       r = LLVMBuildFDiv(Bld, a, b, "fdiv");
    x->mode = Reg;
    x->backend = r;
}

// --- Sets — placeholder ---
void ORG_Singleton(ORG_Item *x) {
    LLVMValueRef i = LoadItem(x);
    LLVMValueRef one = LLVMConstInt(Ty_i32, 1, 0);
    x->mode = Reg;
    x->type = setType;
    x->backend = LLVMBuildShl(Bld, one, i, "set1");
}
// Set range constructor: {lo..hi} → all bits in [lo, hi] set.
// Formula: (~0u >> (31 - hi)) & (~0u << lo) — well-defined for any
// (lo, hi) ∈ [0, 31] without the shift-by-32 UB the naive version hits.
void ORG_Set(ORG_Item *x, ORG_Item *y) {
    LLVMValueRef lo = LoadItem(x);
    LLVMValueRef hi = LoadItem(y);
    LLVMValueRef all_ones = LLVMConstInt(Ty_i32, 0xFFFFFFFF, 0);
    LLVMValueRef thirty_one = LLVMConstInt(Ty_i32, 31, 0);
    LLVMValueRef shr_n = LLVMBuildSub(Bld, thirty_one, hi, "");
    LLVMValueRef hi_mask = LLVMBuildLShr(Bld, all_ones, shr_n, "hi_m");
    LLVMValueRef lo_mask = LLVMBuildShl(Bld, all_ones, lo, "lo_m");
    LLVMValueRef result = LLVMBuildAnd(Bld, hi_mask, lo_mask, "set_range");
    x->mode = Reg;
    x->type = setType;
    x->backend = result;
}
void ORG_In(ORG_Item *x, ORG_Item *y) {
    LLVMValueRef i = LoadItem(x), s = LoadItem(y);
    LLVMValueRef sh = LLVMBuildLShr(Bld, s, i, "shr");
    LLVMValueRef m = LLVMBuildAnd(Bld, sh, LLVMConstInt(Ty_i32, 1, 0), "msk");
    LLVMValueRef c = LLVMBuildICmp(Bld, LLVMIntNE, m, LLVMConstInt(Ty_i32, 0, 0), "in");
    x->mode = Cond;
    x->type = boolType;
    x->backend = c;
}
void ORG_SetOp(LONGINT op, ORG_Item *x, ORG_Item *y) {
    LLVMValueRef a = LoadItem(x), b = LoadItem(y);
    LLVMValueRef r;
    if (op == ORS_plus)       r = LLVMBuildOr (Bld, a, b, "sor");
    else if (op == ORS_minus) r = LLVMBuildAnd(Bld, a, LLVMBuildNot(Bld, b, "n"), "sdiff");
    else if (op == ORS_times) r = LLVMBuildAnd(Bld, a, b, "sand");
    else                      r = LLVMBuildXor(Bld, a, b, "sxor");
    x->mode = Reg;
    x->type = setType;
    x->backend = r;
}

// --- Relations ---
static LLVMIntPredicate icmp_pred(INTEGER op) {
    // ORS_eql=9, neq=10, lss=11, geq=12, leq=13, gtr=14
    switch (op) {
        case ORS_eql: return LLVMIntEQ;
        case ORS_neq: return LLVMIntNE;
        case ORS_lss: return LLVMIntSLT;
        case ORS_geq: return LLVMIntSGE;
        case ORS_leq: return LLVMIntSLE;
        case ORS_gtr: return LLVMIntSGT;
        default: return LLVMIntEQ;
    }
}
static LLVMRealPredicate fcmp_pred(INTEGER op) {
    switch (op) {
        case ORS_eql: return LLVMRealOEQ;
        case ORS_neq: return LLVMRealONE;
        case ORS_lss: return LLVMRealOLT;
        case ORS_geq: return LLVMRealOGE;
        case ORS_leq: return LLVMRealOLE;
        case ORS_gtr: return LLVMRealOGT;
        default: return LLVMRealOEQ;
    }
}

void ORG_IntRelation(INTEGER op, ORG_Item *x, ORG_Item *y) {
    LLVMValueRef a = LoadItem(x), b = LoadItem(y);
    coerce_pair(x, y, &a, &b);
    LLVMValueRef c = LLVMBuildICmp(Bld, icmp_pred(op), a, b, "cmp");
    consume_arc(x, a);
    consume_arc(y, b);
    x->mode = Cond;
    x->type = boolType;
    x->backend = c;
    x->b = 0;
}
void ORG_RealRelation(INTEGER op, ORG_Item *x, ORG_Item *y) {
    LLVMValueRef a = LoadItem(x), b = LoadItem(y);
    LLVMValueRef c = LLVMBuildFCmp(Bld, fcmp_pred(op), a, b, "fcmp");
    x->mode = Cond;
    x->type = boolType;
    x->backend = c;
    x->b = 0;
}
// String / CHAR-array comparison. Falls through to libc strcmp on byte
// pointers — Oberon strings end with 0X, so this is well-defined for any
// CHAR array that has been initialized via string assignment.
void ORG_StringRelation(INTEGER op, ORG_Item *x, ORG_Item *y) {
    LLVMValueRef xp = (x->mode == ORB_Const && x->type && x->type->form == ORB_String)
                    ? (LLVMValueRef)x->backend : LValueItem(x);
    LLVMValueRef yp = (y->mode == ORB_Const && y->type && y->type->form == ORB_String)
                    ? (LLVMValueRef)y->backend : LValueItem(y);
    if (!xp) xp = LLVMConstNull(Ty_ptr);
    if (!yp) yp = LLVMConstNull(Ty_ptr);
    LLVMTypeRef params[2] = { Ty_ptr, Ty_ptr };
    LLVMTypeRef ft = LLVMFunctionType(Ty_i32, params, 2, 0);
    LLVMValueRef fn = LLVMGetNamedFunction(Mod, "strcmp");
    if (!fn) fn = LLVMAddFunction(Mod, "strcmp", ft);
    LLVMValueRef args[2] = { xp, yp };
    LLVMValueRef r = LLVMBuildCall2(Bld, ft, fn, args, 2, "strcmp");
    LLVMValueRef c = LLVMBuildICmp(Bld, icmp_pred(op), r,
                                   LLVMConstInt(Ty_i32, 0, 0), "scmp");
    x->mode = Cond;
    x->type = boolType;
    x->backend = c;
    x->backend2 = NULL;
}

// --- Assignment ---
void ORG_StrToChar(ORG_Item *x) {
    x->type = charType;
    x->orig_type = charType;
}

void ORG_Store(ORG_Item *x, ORG_Item *y) {
    EmittedStmts++;
    LLVMValueRef rhs = LoadItem(y);
    LLVMValueRef addr = LValueItem(x);
    if (!addr) return;

    if (type_is_managed(x->type)) {
        // ARC: retain the new value (unless RHS was a +1-owned function
        // result that we're transferring), release the displaced value,
        // then store. NIL is handled by the runtime helpers.
        BOOLEAN owned = (y->mode == Reg && y->b == 1);
        if (!owned) emit_retain(rhs);
        LLVMValueRef old = LLVMBuildLoad2(Bld, Ty_ptr, addr, "old");
        emit_release(old);
        LLVMBuildStore(Bld, rhs, addr);
        return;
    }

    // Non-pointer scalar — width fix-up if needed, then plain store.
    LLVMTypeRef dst_ty = LlvmType(x->type);
    LLVMTypeRef src_ty = LLVMTypeOf(rhs);
    if (src_ty != dst_ty) {
        if (LLVMGetTypeKind(src_ty) == LLVMIntegerTypeKind &&
            LLVMGetTypeKind(dst_ty) == LLVMIntegerTypeKind) {
            unsigned sb = LLVMGetIntTypeWidth(src_ty);
            unsigned db = LLVMGetIntTypeWidth(dst_ty);
            if (db < sb)      rhs = LLVMBuildTrunc(Bld, rhs, dst_ty, "tr");
            else if (db > sb) rhs = LLVMBuildSExt(Bld,  rhs, dst_ty, "sx");
        }
    }
    LLVMBuildStore(Bld, rhs, addr);
}

void ORG_StoreStruct(ORG_Item *x, ORG_Item *y) {
    EmittedStmts++;
    if (x->type && x->type->form == ORB_Record &&
        record_has_ptr_fields(x->type)) {
        // ARC-aware: retain src's ptr fields, release dst's, then memcpy
        // the body (preserving dst's {tag, _rc} header).
        LLVMValueRef td = record_td(x->type);
        LLVMTypeRef pt[3] = { Ty_ptr, Ty_ptr, Ty_ptr };
        LLVMTypeRef ft = LLVMFunctionType(Ty_void, pt, 3, 0);
        LLVMValueRef fn = LLVMGetNamedFunction(Mod, "oc_record_assign");
        if (!fn) fn = LLVMAddFunction(Mod, "oc_record_assign", ft);
        LLVMValueRef args[3] = { LValueItem(x), LValueItem(y), td };
        LLVMBuildCall2(Bld, ft, fn, args, 3, "");
        return;
    }
    LLVMTypeRef ty = LlvmType(x->type);
    LLVMValueRef sz = LLVMSizeOf(ty);
    LLVMBuildMemCpy(Bld, LValueItem(x), 0, LValueItem(y), 0, sz);
}

// CHAR-array := string-literal: memcpy from the private string global.
void ORG_CopyString(ORG_Item *x, ORG_Item *y) {
    EmittedStmts++;
    LLVMValueRef dst = LValueItem(x);
    LLVMValueRef src = (LLVMValueRef)y->backend;
    if (!dst || !src) return;
    LLVMValueRef sz = LLVMConstInt(Ty_i64, (uint64_t)y->b, 0);
    LLVMBuildMemCpy(Bld, dst, 0, src, 0, sz);
}

// --- Parameter passing ---
void ORG_OpenArrayParam(ORG_Item *x) {
    if (CallTop < 0 || CallArgC[CallTop] + 1 >= MAX_CALL_ARGS) return;
    LLVMValueRef ptr;
    LLVMValueRef len;
    if (x->type && x->type->form == ORB_Array && x->type->len < 0 && x->backend2) {
        // Actual is itself an open-array param. Pass through.
        ptr = (LLVMValueRef)x->backend;
        len = (LLVMValueRef)x->backend2;
    } else if (x->type && x->type->form == ORB_Array && x->type->len > 0) {
        // Static array: ptr = base, length = compile-time constant.
        ptr = LValueItem(x);
        len = LLVMConstInt(Ty_i32, (uint64_t)x->type->len, 0);
    } else {
        // Fallback — pass ptr and 0.
        ptr = LValueItem(x);
        len = LLVMConstInt(Ty_i32, 0, 0);
    }
    CallArgs[CallTop][CallArgC[CallTop]++] = ptr;
    CallArgs[CallTop][CallArgC[CallTop]++] = len;
}
void ORG_VarParam(ORG_Item *x, ORB_Type *ftype) {
    if (CallTop < 0 || CallArgC[CallTop] >= MAX_CALL_ARGS) return;
    /* Open-array VAR / promoted-value param: ABI is (ptr, i32 len). The
       parser dispatches here when CompTypes matches actual to formal
       open-array, so we still need to forward the length descriptor. */
    if (ftype && ftype->form == ORB_Array && ftype->len < 0) {
        LLVMValueRef ptr, len;
        if (x->type && x->type->form == ORB_Array && x->type->len < 0 && x->backend2) {
            ptr = (LLVMValueRef)x->backend;
            len = (LLVMValueRef)x->backend2;
        } else if (x->type && x->type->form == ORB_Array && x->type->len > 0) {
            ptr = LValueItem(x);
            len = LLVMConstInt(Ty_i32, (uint64_t)x->type->len, 0);
        } else {
            ptr = LValueItem(x);
            len = LLVMConstInt(Ty_i32, 0, 0);
        }
        if (CallArgC[CallTop] + 1 >= MAX_CALL_ARGS) return;
        CallArgs[CallTop][CallArgC[CallTop]++] = ptr;
        CallArgs[CallTop][CallArgC[CallTop]++] = len;
        return;
    }
    CallArgs[CallTop][CallArgC[CallTop]++] = LValueItem(x);
}
void ORG_ValueParam(ORG_Item *x) {
    if (CallTop < 0 || CallArgC[CallTop] >= MAX_CALL_ARGS) return;
    LLVMValueRef v = LoadItem(x);
    int slot = CallArgC[CallTop];
    CallArgs[CallTop][slot] = v;
    // If the argument is a +1-owned function-call result, the caller still
    // owns one reference. The callee will retain on entry (taking its own),
    // so after the call returns we need to release this leftover ref.
    CallArgOwned[CallTop][slot] =
        (x->mode == Reg && x->b == 1 && type_is_managed(x->type));
    CallArgC[CallTop]++;
}
void ORG_StringParam(ORG_Item *x) {
    if (CallTop < 0 || CallArgC[CallTop] + 1 >= MAX_CALL_ARGS) return;
    LLVMValueRef ptr = x->backend ? (LLVMValueRef)x->backend : LValueItem(x);
    if (!ptr) ptr = LLVMConstNull(Ty_ptr);
    LLVMValueRef len = LLVMConstInt(Ty_i32, (uint64_t)x->b, 0);
    CallArgs[CallTop][CallArgC[CallTop]++] = ptr;
    CallArgs[CallTop][CallArgC[CallTop]++] = len;
}

// --- FOR ---
// Parser invokes:
//   For0(x, y)              // x := y                       (initial assignment)
//   L0 := Here()            // top of loop
//   For1(x, y, z, w, &L1)   // if !(x <= z) goto exit       (sense flips for w<0)
//                           // L1 chains the exit branches
//   ...body...
//   For2(x, y, w)           // x := x + w
//   BJump(L0)
//   FixLink(L1)
void ORG_For0(ORG_Item *x, ORG_Item *y) {
    EmittedStmts++;
    LLVMValueRef rhs = LoadItem(y);
    LLVMTypeRef dst_ty = LlvmType(x->type);
    LLVMTypeRef src_ty = LLVMTypeOf(rhs);
    if (src_ty != dst_ty &&
        LLVMGetTypeKind(src_ty) == LLVMIntegerTypeKind &&
        LLVMGetTypeKind(dst_ty) == LLVMIntegerTypeKind) {
        unsigned sb = LLVMGetIntTypeWidth(src_ty), db = LLVMGetIntTypeWidth(dst_ty);
        if (db < sb)      rhs = LLVMBuildTrunc(Bld, rhs, dst_ty, "tr");
        else if (db > sb) rhs = LLVMBuildSExt(Bld,  rhs, dst_ty, "sx");
    }
    LLVMBuildStore(Bld, rhs, LValueItem(x));
}

void ORG_For1(ORG_Item *x, ORG_Item *y, ORG_Item *z, ORG_Item *w, LONGINT *L) {
    (void)y;
    LLVMValueRef xv = LoadItem(x);
    LLVMValueRef zv = LoadItem(z);
    if (LLVMTypeOf(zv) != LLVMTypeOf(xv) &&
        LLVMGetTypeKind(LLVMTypeOf(zv)) == LLVMIntegerTypeKind &&
        LLVMGetTypeKind(LLVMTypeOf(xv)) == LLVMIntegerTypeKind) {
        zv = LLVMBuildIntCast2(Bld, zv, LLVMTypeOf(xv), 1, "zw");
    }
    // step is a const (parser CheckConst'd it). Sign decides loop direction.
    LLVMIntPredicate pred = (w->mode == ORB_Const && w->a < 0)
        ? LLVMIntSGE   // descending: continue while x >= z
        : LLVMIntSLE;  // ascending:  continue while x <= z
    LLVMValueRef cont = LLVMBuildICmp(Bld, pred, xv, zv, "fortest");
    LLVMBasicBlockRef body_bb = append_block("for_body");
    LLVMBasicBlockRef exit_bb = append_block("for_exit");
    LLVMBuildCondBr(Bld, cont, body_bb, exit_bb);
    LLVMPositionBuilderAtEnd(Bld, body_bb);
    // Parser doesn't initialize *L before calling — start a fresh chain.
    *L = new_label(exit_bb, 0);
}

void ORG_For2(ORG_Item *x, ORG_Item *y, ORG_Item *w) {
    (void)y;
    EmittedStmts++;
    LLVMValueRef xv = LoadItem(x);
    LLVMValueRef wv = LoadItem(w);
    if (LLVMTypeOf(wv) != LLVMTypeOf(xv) &&
        LLVMGetTypeKind(LLVMTypeOf(wv)) == LLVMIntegerTypeKind &&
        LLVMGetTypeKind(LLVMTypeOf(xv)) == LLVMIntegerTypeKind) {
        wv = LLVMBuildIntCast2(Bld, wv, LLVMTypeOf(xv), 1, "ww");
    }
    LLVMValueRef nw = LLVMBuildAdd(Bld, xv, wv, "for_step");
    LLVMBuildStore(Bld, nw, LValueItem(x));
}

// --- CASE ---
//
// Parser sequence per arm (NumericCaseArm):
//   CaseLabelList → CaseLabel/CaseRange for each label,
//                   each adds a forward branch to *hitChain on match
//                   and falls through on miss
//   FJump(&missLink)        ; if all labels missed, jump to next arm
//   FixLink(hitChain)       ; matched labels land here, body emits
//   StatSequence            ; arm body
//   FJump(&endChain)        ; jump past CASE
//   FixOne(missLink)        ; next arm continues from here
//
// CaseLabel emits a single equality test and a conditional branch:
// hit→add to chain, miss→continue testing.
void ORG_CaseLabel(ORG_Item *x, LONGINT val, LONGINT *chain) {
    LLVMValueRef xv = LoadItem(x);
    LLVMTypeRef xt = LLVMTypeOf(xv);
    LLVMValueRef vv = LLVMConstInt(xt, (uint64_t)(int64_t)val, 1);
    LLVMValueRef cond = LLVMBuildICmp(Bld, LLVMIntEQ, xv, vv, "case_eq");
    LLVMBasicBlockRef hit  = append_block("case_hit");
    LLVMBasicBlockRef miss = append_block("case_miss");
    LLVMBuildCondBr(Bld, cond, hit, miss);
    LLVMPositionBuilderAtEnd(Bld, miss);
    *chain = new_label(hit, (int)*chain);
}

// CaseRange: lo <= x <= hi.
void ORG_CaseRange(ORG_Item *x, LONGINT lo, LONGINT hi, LONGINT *chain) {
    LLVMValueRef xv = LoadItem(x);
    LLVMTypeRef xt = LLVMTypeOf(xv);
    LLVMValueRef lov = LLVMConstInt(xt, (uint64_t)(int64_t)lo, 1);
    LLVMValueRef hiv = LLVMConstInt(xt, (uint64_t)(int64_t)hi, 1);
    LLVMValueRef ge = LLVMBuildICmp(Bld, LLVMIntSGE, xv, lov, "ge");
    LLVMValueRef le = LLVMBuildICmp(Bld, LLVMIntSLE, xv, hiv, "le");
    LLVMValueRef in = LLVMBuildAnd(Bld, ge, le, "in_range");
    LLVMBasicBlockRef hit  = append_block("case_hit");
    LLVMBasicBlockRef miss = append_block("case_miss");
    LLVMBuildCondBr(Bld, in, hit, miss);
    LLVMPositionBuilderAtEnd(Bld, miss);
    *chain = new_label(hit, (int)*chain);
}

// --- Branches / control flow ---
LONGINT ORG_Here(void) {
    // Mark current point as a label by ensuring a fresh BB starts here.
    LLVMBasicBlockRef cur = LLVMGetInsertBlock(Bld);
    if (cur && LLVMGetBasicBlockTerminator(cur) == NULL) {
        LLVMBasicBlockRef bb = append_block("here");
        LLVMBuildBr(Bld, bb);
        LLVMPositionBuilderAtEnd(Bld, bb);
        return new_label(bb, 0);
    }
    LLVMBasicBlockRef bb = append_block("here");
    LLVMPositionBuilderAtEnd(Bld, bb);
    return new_label(bb, 0);
}

void ORG_FJump(LONGINT *L) {
    LLVMBasicBlockRef pending = append_block("fwd");
    if (!current_block_terminated()) {
        LLVMBuildBr(Bld, pending);
    }
    int id = new_label(pending, (int)*L);
    *L = id;
    // Position builder at an unreachable BB so subsequent emits don't bleed
    // into the chain link's BB before its terminator is set in FixLink.
    LLVMBasicBlockRef dead = append_block("dead");
    LLVMPositionBuilderAtEnd(Bld, dead);
}

void ORG_CFJump(ORG_Item *x) {
    EmittedStmts++;
    LLVMValueRef cond = LoadItem(x);
    LLVMTypeRef ct = LLVMTypeOf(cond);
    if (ct != Ty_i1) {
        cond = LLVMBuildICmp(Bld, LLVMIntNE, cond, LLVMConstInt(ct, 0, 0), "tobool");
    }
    LLVMBasicBlockRef true_bb  = append_block("if_t");
    LLVMBasicBlockRef false_bb = append_block("if_f");
    LLVMBuildCondBr(Bld, cond, true_bb, false_bb);
    LLVMPositionBuilderAtEnd(Bld, true_bb);
    int id = new_label(false_bb, 0);
    x->a = id;
    x->mode = Cond;
}

void ORG_BJump(LONGINT L) {
    if ((int)L > 0 && (int)L <= LabelCount) {
        if (!current_block_terminated()) {
            LLVMBuildBr(Bld, Labels[(int)L].bb);
        }
        LLVMBasicBlockRef dead = append_block("dead");
        LLVMPositionBuilderAtEnd(Bld, dead);
    }
}

void ORG_CBJump(ORG_Item *x, LONGINT L) {
    /* Emitted at the bottom of `REPEAT body UNTIL cond` — branch back
       to the loop head L when cond is FALSE, fall through to cont
       when cond is TRUE. Same false-back semantics as NW's original
       RISC `BNZ L` for the UNTIL terminator. */
    EmittedStmts++;
    LLVMValueRef cond = LoadItem(x);
    LLVMTypeRef ct = LLVMTypeOf(cond);
    if (ct != Ty_i1) {
        cond = LLVMBuildICmp(Bld, LLVMIntNE, cond, LLVMConstInt(ct, 0, 0), "tobool");
    }
    LLVMBasicBlockRef cont = append_block("cb_cont");
    if ((int)L > 0 && (int)L <= LabelCount) {
        LLVMBuildCondBr(Bld, cond, cont, Labels[(int)L].bb);
    } else {
        LLVMBuildCondBr(Bld, cond, cont, cont);
    }
    LLVMPositionBuilderAtEnd(Bld, cont);
}

void ORG_Fixup(ORG_Item *x) {
    if (x->a > 0 && x->a <= LabelCount) {
        if (!current_block_terminated()) {
            // Emit fall-through to the false target
            LLVMBuildBr(Bld, Labels[(int)x->a].bb);
        }
        LLVMPositionBuilderAtEnd(Bld, Labels[(int)x->a].bb);
    }
}

// FixOne: take the single forward branch parked at label `at` and point it
// at a fresh BB; position the builder at that fresh BB. Used by CASE arms
// to chain "no label matched" into the next arm's tests (or the ELSE / end).
void ORG_FixOne(LONGINT at) {
    if (at <= 0 || at > LabelCount) return;
    LLVMBasicBlockRef pending = Labels[(int)at].bb;
    LLVMBasicBlockRef next = append_block("after_fixone");
    // The current block is typically the "dead" BB that ORG_FJump created
    // after emitting its forward branch. It needs a terminator too.
    if (!current_block_terminated()) {
        LLVMBuildBr(Bld, next);
    }
    if (!LLVMGetBasicBlockTerminator(pending)) {
        LLVMPositionBuilderAtEnd(Bld, pending);
        LLVMBuildBr(Bld, next);
    }
    LLVMPositionBuilderAtEnd(Bld, next);
}

void ORG_FixLink(LONGINT L) {
    if (L == 0) return;
    LLVMBasicBlockRef merge = append_block("merge");
    // Fall-through from the current block (e.g. end of ELSE body).
    if (!current_block_terminated()) {
        LLVMBuildBr(Bld, merge);
    }
    int id = (int)L;
    while (id > 0) {
        LLVMBasicBlockRef bb = Labels[id].bb;
        if (!LLVMGetBasicBlockTerminator(bb)) {
            LLVMPositionBuilderAtEnd(Bld, bb);
            LLVMBuildBr(Bld, merge);
        }
        id = Labels[id].next;
    }
    LLVMPositionBuilderAtEnd(Bld, merge);
}

// --- Procedure calls ---
void ORG_PrepCall(ORG_Item *x, LONGINT *r) {
    (void)x;
    if (CallTop + 1 >= MAX_CALL_DEPTH) {
        ORS_Mark("call stack overflow");
        *r = 0;
        return;
    }
    CallTop++;
    CallArgC[CallTop] = 0;
    for (int i = 0; i < MAX_CALL_ARGS; i++) CallArgOwned[CallTop][i] = FALSE;
    *r = CallTop;
}

void ORG_Call(ORG_Item *x, LONGINT r) {
    EmittedStmts++;
    LLVMValueRef fn;
    LLVMTypeRef  ft = ProcType(x->type);   // x->type is the proc type
    // Direct procedure references (e.g. `Foo()` where Foo is a named
    // procedure) arrive with mode == ORB_Const and backend pointing at the
    // LLVM function. Procedure variables / fields / params have an L-value
    // backend — we need to load to get the function pointer to call.
    if (x->mode == ORB_Const && x->backend) {
        fn = (LLVMValueRef)x->backend;
    } else {
        fn = LoadItem(x);
    }
    BOOLEAN has_result = x->type->base && x->type->base->form != ORB_NoTyp;
    // Mark only strong-pointer results as +1-owned. WEAK returns aren't
    // retained by the callee, so the caller has no reference to release.
    BOOLEAN ptr_result = has_result && type_is_managed(x->type->base);
    LLVMValueRef result = LLVMBuildCall2(Bld, ft, fn,
        CallArgs[(int)r], CallArgC[(int)r],
        has_result ? "call" : "");

    // Release the leftover +1 references from owned arguments. Callee
    // already retained on entry and released on exit, so this purely
    // balances out the caller's own +1.
    for (int i = 0; i < CallArgC[(int)r]; i++) {
        if (CallArgOwned[(int)r][i]) {
            emit_release(CallArgs[(int)r][i]);
            CallArgOwned[(int)r][i] = FALSE;
        }
    }
    // Do NOT mutate x->type here — the parser sets x->type = x->type->base
    // after returning from ORG_Call.
    if (has_result) {
        x->mode = Reg;
        x->backend = result;
        // ARC ownership marker. The callee returned at +1 (it retained the
        // return value before its own cleanup, so the value survives). The
        // caller is expected to consume that +1 — typically by storing,
        // which "transfers" without an extra retain. b=1 signals this.
        x->b = ptr_result ? 1 : 0;
    } else {
        x->mode = Reg;
        x->backend = NULL;
        x->b = 0;
    }
    if ((int)r == CallTop) CallTop--;
}

// --- Procedure entry / exit ---
void ORG_Enter(ORB_Object *proc, ORB_Object *params, LONGINT parblksize, LONGINT locblksize, BOOLEAN int_proc) {
    (void)parblksize; (void)locblksize; (void)int_proc;

    LLVMValueRef fn = LookupProc(proc);
    if (!proc->expo) LLVMSetLinkage(fn, LLVMInternalLinkage);
    CurFn = fn;

    LLVMBasicBlockRef entry = LLVMAppendBasicBlockInContext(Ctx, fn, "entry");
    LLVMPositionBuilderAtEnd(Bld, entry);

    NumLocalPtrs = 0;
    NumLocalRecs = 0;
    NumLocalArrs = 0;

    // Params first (proc->type->nofpar of them). ORB_Par params (VAR or
    // ORP-promoted structured value params) get a pointer slot; scalar value
    // params get a slot of their value type. Open-array params consume 2
    // function args (ptr + length) and get a separate length alloca.
    int nparams = proc->type->nofpar;
    int idx = 0, llvm_idx = 0;
    ORB_Object *p = params;
    while (p && idx < nparams) {
        if (is_open_array(p)) {
            LLVMValueRef ptr_arg = LLVMGetParam(fn, llvm_idx++);
            LLVMValueRef len_arg = LLVMGetParam(fn, llvm_idx++);
            LLVMValueRef pslot = LLVMBuildAlloca(Bld, Ty_ptr, p->name);
            LLVMBuildStore(Bld, ptr_arg, pslot);
            char lname[64];
            snprintf(lname, sizeof(lname), "%s_len", p->name);
            LLVMValueRef lslot = LLVMBuildAlloca(Bld, Ty_i32, lname);
            LLVMBuildStore(Bld, len_arg, lslot);
            p->backend = pslot;
            p->backend2 = lslot;
        } else {
            LLVMValueRef arg = LLVMGetParam(fn, llvm_idx++);
            LLVMTypeRef slot_ty = (p->class == ORB_Par) ? Ty_ptr : LlvmType(p->type);
            LLVMValueRef slot = LLVMBuildAlloca(Bld, slot_ty, p->name);
            LLVMBuildStore(Bld, arg, slot);
            p->backend = slot;

            // ARC: a value pointer param is a +0 borrow from the caller.
            // Retain it on entry so we can release it on exit symmetrically
            // with locals. VAR pointer params are not retained — the
            // caller owns the target's lifetime; we just modify their slot.
            if (p->class == ORB_Var && type_is_managed(p->type)) {
                emit_retain(arg);
                if (NumLocalPtrs < MAX_LOCAL_PTRS) {
                    LocalPtrSlots[NumLocalPtrs++] = slot;
                }
            }
        }
        idx++; p = p->next;
    }
    // Remaining objects in this scope are locals.
    while (p) {
        if (p->class == ORB_Var) {
            LLVMTypeRef ty = LlvmType(p->type);
            LLVMValueRef slot = LLVMBuildAlloca(Bld, ty, p->name);
            p->backend = slot;

            // ARC: pointer locals start as NIL so the first store's
            // release-of-old is a safe no-op. They get released on exit.
            if (type_is_managed(p->type)) {
                LLVMBuildStore(Bld, LLVMConstNull(Ty_ptr), slot);
                if (NumLocalPtrs < MAX_LOCAL_PTRS) {
                    LocalPtrSlots[NumLocalPtrs++] = slot;
                }
            }
            // ARC: record locals with pointer fields get zero-initialised
            // (so cleanup reads NIL on uninitialised cells), have their
            // tag/_rc header set to a sane state (tag = TD, refcount =
            // immortal sentinel so the stack record is never accidentally
            // free()d), and get tracked for scope-exit field-release.
            else if (p->type && p->type->form == ORB_Record &&
                     record_has_ptr_fields(p->type)) {
                LLVMValueRef sz = LLVMSizeOf(ty);
                LLVMBuildMemSet(Bld, slot, LLVMConstInt(Ty_i8, 0, 0), sz, 0);
                LLVMValueRef td = record_td(p->type);
                LLVMValueRef tag_slot = LLVMBuildStructGEP2(Bld, ty, slot, 0, "tag_slot");
                LLVMBuildStore(Bld, td, tag_slot);
                LLVMValueRef rc_slot = LLVMBuildStructGEP2(Bld, ty, slot, 1, "rc_slot");
                LLVMBuildStore(Bld, LLVMConstInt(Ty_i64, -1, 1), rc_slot);
                if (NumLocalRecs < MAX_LOCAL_RECS) {
                    LocalRecSlots[NumLocalRecs] = slot;
                    LocalRecTds  [NumLocalRecs] = td;
                    NumLocalRecs++;
                }
            }
            // ARC: array locals whose elements are managed (pointers, or
            // records with pointer fields). Zero-init so cleanup reads NIL
            // on uninitialised slots; track for scope-exit release loop.
            else if (p->type && p->type->form == ORB_Array && p->type->len > 0) {
                ORB_Type *elt = p->type->base;
                BOOLEAN ptr_array = elt && elt->form == ORB_Pointer && !elt->weak;
                BOOLEAN rec_array = elt && elt->form == ORB_Record &&
                                    record_has_ptr_fields(elt);
                if ((ptr_array || rec_array) && NumLocalArrs < MAX_LOCAL_ARRS) {
                    LLVMValueRef sz = LLVMSizeOf(ty);
                    LLVMBuildMemSet(Bld, slot, LLVMConstInt(Ty_i8, 0, 0), sz, 0);
                    LocalArrs[NumLocalArrs].slot = slot;
                    LocalArrs[NumLocalArrs].len  = p->type->len;
                    if (rec_array) {
                        LocalArrs[NumLocalArrs].elem_td   = record_td(elt);
                        LocalArrs[NumLocalArrs].elem_size = elt->size;
                    } else {
                        LocalArrs[NumLocalArrs].elem_td   = NULL;
                        LocalArrs[NumLocalArrs].elem_size = 0;
                    }
                    NumLocalArrs++;
                }
            }
        }
        p = p->next;
    }

    // Start counting body statements from here.
    EmittedStmts = 0;
}

void ORG_Return(ORB_Object *proc, ORG_Item *x) {
    BOOLEAN returns_value = proc->type->base && proc->type->base->form != ORB_NoTyp;
    // WEAK returns aren't retained — callers don't release them.
    BOOLEAN returns_ptr   = returns_value && type_is_managed(proc->type->base);
    LLVMValueRef rv = NULL;

    if (returns_value) {
        rv = (x && x->type && x->type->form != ORB_NoTyp)
                        ? LoadItem(x)
                        : LLVMConstNull(LlvmType(proc->type->base));
        LLVMTypeRef ret_ty = LlvmType(proc->type->base);
        LLVMTypeRef rv_ty = LLVMTypeOf(rv);
        if (rv_ty != ret_ty &&
            LLVMGetTypeKind(rv_ty) == LLVMIntegerTypeKind &&
            LLVMGetTypeKind(ret_ty) == LLVMIntegerTypeKind) {
            unsigned sb = LLVMGetIntTypeWidth(rv_ty), db = LLVMGetIntTypeWidth(ret_ty);
            if (db < sb)      rv = LLVMBuildTrunc(Bld, rv, ret_ty, "rtr");
            else if (db > sb) rv = LLVMBuildSExt(Bld,  rv, ret_ty, "rsx");
        }

        // ARC: retain the return value BEFORE releasing locals — the value
        // may itself be one of the local slots. This makes the function
        // hand off a +1 reference to the caller; the caller's store will
        // also retain (yielding +2) which the caller's later release
        // balances. LLVM's optimizer can fold the redundant pair when it
        // sees through the calls.
        if (returns_ptr) emit_retain(rv);
    }

    // Release every tracked pointer local / value pointer param.
    for (int i = 0; i < NumLocalPtrs; i++) {
        LLVMValueRef cur = LLVMBuildLoad2(Bld, Ty_ptr, LocalPtrSlots[i], "lp");
        emit_release(cur);
    }

    // For each stack record local with pointer fields, walk the TD's
    // ptr_offsets and release each child via the runtime helper. The slot
    // itself isn't freed (it's stack memory).
    if (NumLocalRecs > 0) {
        LLVMTypeRef pt[2] = { Ty_ptr, Ty_ptr };
        LLVMTypeRef ft = LLVMFunctionType(Ty_void, pt, 2, 0);
        LLVMValueRef fn = LLVMGetNamedFunction(Mod, "oc_release_fields");
        if (!fn) fn = LLVMAddFunction(Mod, "oc_release_fields", ft);
        for (int i = 0; i < NumLocalRecs; i++) {
            LLVMValueRef args[2] = { LocalRecSlots[i], LocalRecTds[i] };
            LLVMBuildCall2(Bld, ft, fn, args, 2, "");
        }
    }

    // Stack arrays of managed elements.
    for (int i = 0; i < NumLocalArrs; i++) {
        if (LocalArrs[i].elem_td) {
            // ARRAY OF record-with-ptr-fields → oc_release_array_fields
            LLVMTypeRef pt[4] = { Ty_ptr, Ty_i64, Ty_i64, Ty_ptr };
            LLVMTypeRef ft = LLVMFunctionType(Ty_void, pt, 4, 0);
            LLVMValueRef fn = LLVMGetNamedFunction(Mod, "oc_release_array_fields");
            if (!fn) fn = LLVMAddFunction(Mod, "oc_release_array_fields", ft);
            LLVMValueRef args[4] = {
                LocalArrs[i].slot,
                LLVMConstInt(Ty_i64, (uint64_t)LocalArrs[i].len, 0),
                LLVMConstInt(Ty_i64, (uint64_t)LocalArrs[i].elem_size, 0),
                LocalArrs[i].elem_td,
            };
            LLVMBuildCall2(Bld, ft, fn, args, 4, "");
        } else {
            // ARRAY OF POINTER → oc_release_array
            LLVMTypeRef pt[2] = { Ty_ptr, Ty_i64 };
            LLVMTypeRef ft = LLVMFunctionType(Ty_void, pt, 2, 0);
            LLVMValueRef fn = LLVMGetNamedFunction(Mod, "oc_release_array");
            if (!fn) fn = LLVMAddFunction(Mod, "oc_release_array", ft);
            LLVMValueRef args[2] = {
                LocalArrs[i].slot,
                LLVMConstInt(Ty_i64, (uint64_t)LocalArrs[i].len, 0),
            };
            LLVMBuildCall2(Bld, ft, fn, args, 2, "");
        }
    }

    if (returns_value) {
        if (!current_block_terminated()) LLVMBuildRet(Bld, rv);
    } else {
        if (!current_block_terminated()) LLVMBuildRetVoid(Bld);
    }

    // Signature-stub auto-detection: an exported procedure whose body emitted
    // no real statements is treated as a hand-off to whatever runtime
    // provides a strong definition. Mark it weak so a C/Oberon override
    // links cleanly without a duplicate-symbol error. Includes functions
    // whose body is just `RETURN NIL` / `RETURN 0` — common stub pattern
    // for typed-result procedures we expect a runtime to override.
    if (proc->expo && EmittedStmts == 0 && proc->backend) {
        LLVMSetLinkage((LLVMValueRef)proc->backend, LLVMWeakAnyLinkage);
    }

    CurFn = ModInit;   // resume module-init context (set up later in ORG_Header)
}

// --- Built-ins ---
void ORG_Increment(LONGINT upordown, ORG_Item *x, ORG_Item *y) {
    EmittedStmts++;
    LLVMValueRef cur = LoadItem(x);
    LLVMValueRef step = LoadItem(y);
    if (LLVMTypeOf(step) != LLVMTypeOf(cur) &&
        LLVMGetTypeKind(LLVMTypeOf(step)) == LLVMIntegerTypeKind &&
        LLVMGetTypeKind(LLVMTypeOf(cur))  == LLVMIntegerTypeKind) {
        step = LLVMBuildIntCast2(Bld, step, LLVMTypeOf(cur), 1, "stp");
    }
    LLVMValueRef nw = (upordown == 0)
        ? LLVMBuildAdd(Bld, cur, step, "inc")
        : LLVMBuildSub(Bld, cur, step, "dec");
    LLVMBuildStore(Bld, nw, LValueItem(x));
}
// INCL(s, n) → s OR (1 << n);  EXCL(s, n) → s AND NOT (1 << n).
// Parser sets `inorex` to 0 for INCL, 1 for EXCL.
void ORG_Include(LONGINT inorex, ORG_Item *x, ORG_Item *y) {
    EmittedStmts++;
    LLVMValueRef addr = LValueItem(x);
    LLVMValueRef cur  = LLVMBuildLoad2(Bld, Ty_i32, addr, "set");
    LLVMValueRef bit  = LoadItem(y);
    LLVMValueRef one  = LLVMConstInt(Ty_i32, 1, 0);
    LLVMValueRef mask = LLVMBuildShl(Bld, one, bit, "mask");
    LLVMValueRef nw;
    if (inorex == 0) {
        nw = LLVMBuildOr(Bld, cur, mask, "incl");
    } else {
        LLVMValueRef notmask = LLVMBuildNot(Bld, mask, "nmask");
        nw = LLVMBuildAnd(Bld, cur, notmask, "excl");
    }
    LLVMBuildStore(Bld, nw, addr);
}
void ORG_Assert(ORG_Item *x) { EmittedStmts++; (void)x; }

void ORG_New(ORG_Item *x) {
    EmittedStmts++;
    if (!x->type || x->type->form != ORB_Pointer) {
        ORS_Mark("NEW: not a pointer");
        return;
    }
    ORB_Type *base = x->type->base;
    if (!base || base->form != ORB_Record) {
        ORS_Mark("NEW: pointer base must be record");
        return;
    }

    // oc_alloc(td) — runtime reads td.size, zero-initialises everything,
    // sets the tag, and leaves refcount at 0. The surrounding store will
    // call oc_retain to bring the count to 1, uniform with `p := other`.
    LLVMValueRef td = record_td(base);
    LLVMTypeRef alloc_pt[1] = { Ty_ptr };
    LLVMTypeRef alloc_ft = LLVMFunctionType(Ty_ptr, alloc_pt, 1, 0);
    LLVMValueRef alloc_fn = LLVMGetNamedFunction(Mod, "oc_alloc");
    if (!alloc_fn) alloc_fn = LLVMAddFunction(Mod, "oc_alloc", alloc_ft);
    LLVMValueRef args[1] = { td };
    LLVMValueRef raw = LLVMBuildCall2(Bld, alloc_ft, alloc_fn, args, 1, "new");

    // Same pattern as ORG_Store on a pointer: retain new, release old, store.
    // After this, the slot holds a +1 reference to the fresh object.
    LLVMValueRef addr = LValueItem(x);
    emit_retain(raw);
    LLVMValueRef old = LLVMBuildLoad2(Bld, Ty_ptr, addr, "old");
    emit_release(old);
    LLVMBuildStore(Bld, raw, addr);
}
void ORG_Pack(ORG_Item *x, ORG_Item *y) { EmittedStmts++; (void)x; (void)y; }
void ORG_Unpk(ORG_Item *x, ORG_Item *y) { EmittedStmts++; (void)x; (void)y; }

// Helper for SYSTEM.GET/PUT/COPY: convert an integer-valued address Item
// into an LLVM `ptr`. INTEGER (i32) gets zero-extended to i64 first to
// avoid losing high bits on a 64-bit host.
static LLVMValueRef addr_to_ptr(ORG_Item *x) {
    LLVMValueRef a = LoadItem(x);
    LLVMTypeRef at = LLVMTypeOf(a);
    if (LLVMGetTypeKind(at) == LLVMIntegerTypeKind) {
        unsigned w = LLVMGetIntTypeWidth(at);
        if (w < 64) a = LLVMBuildZExt(Bld, a, Ty_i64, "ext");
    }
    return LLVMBuildIntToPtr(Bld, a, Ty_ptr, "addr");
}

// SYSTEM.GET(addr, VAR var) — load from `addr` into `var`.
void ORG_Get(ORG_Item *addr, ORG_Item *var) {
    EmittedStmts++;
    LLVMValueRef p = addr_to_ptr(addr);
    LLVMTypeRef vt = LlvmType(var->type);
    LLVMValueRef v = LLVMBuildLoad2(Bld, vt, p, "get");
    LLVMBuildStore(Bld, v, LValueItem(var));
}

// SYSTEM.PUT(addr, val) — store `val` at `addr`.
void ORG_Put(ORG_Item *addr, ORG_Item *val) {
    EmittedStmts++;
    LLVMValueRef p = addr_to_ptr(addr);
    LLVMValueRef v = LoadItem(val);
    LLVMBuildStore(Bld, v, p);
}

// SYSTEM.COPY(srcAddr, dstAddr, n) — memcpy n bytes.
void ORG_Copy(ORG_Item *src, ORG_Item *dst, ORG_Item *n) {
    EmittedStmts++;
    LLVMValueRef sp = addr_to_ptr(src);
    LLVMValueRef dp = addr_to_ptr(dst);
    LLVMValueRef nv = LoadItem(n);
    if (LLVMTypeOf(nv) != Ty_i64) {
        nv = LLVMBuildZExt(Bld, nv, Ty_i64, "next");
    }
    LLVMBuildMemCpy(Bld, dp, 0, sp, 0, nv);
}
void ORG_Abs(ORG_Item *x) {
    LLVMValueRef v = LoadItem(x);
    if (x->type && x->type->form == ORB_Real) {
        x->mode = Reg;
        x->backend = v;   // TODO: fabs
        return;
    }
    LLVMValueRef neg = LLVMBuildNeg(Bld, v, "abs.n");
    LLVMValueRef c = LLVMBuildICmp(Bld, LLVMIntSLT, v, LLVMConstInt(LLVMTypeOf(v), 0, 0), "abs.c");
    x->mode = Reg;
    x->backend = LLVMBuildSelect(Bld, c, neg, v, "abs");
}
void ORG_Odd(ORG_Item *x) {
    LLVMValueRef v = LoadItem(x);
    LLVMValueRef m = LLVMBuildAnd(Bld, v, LLVMConstInt(LLVMTypeOf(v), 1, 0), "oddm");
    x->mode = Cond;
    x->type = boolType;
    x->backend = LLVMBuildICmp(Bld, LLVMIntNE, m, LLVMConstInt(LLVMTypeOf(v), 0, 0), "odd");
    x->orig_type = boolType;
}
void ORG_Floor(ORG_Item *x) {
    // Oberon FLOOR rounds toward -∞; LLVM fptosi truncates toward zero.
    // Apply llvm.floor.f32 first, then convert.
    LLVMValueRef v = LoadItem(x);
    LLVMTypeRef pt[1] = { Ty_float };
    LLVMTypeRef ft = LLVMFunctionType(Ty_float, pt, 1, 0);
    LLVMValueRef floor_fn = LLVMGetNamedFunction(Mod, "llvm.floor.f32");
    if (!floor_fn) floor_fn = LLVMAddFunction(Mod, "llvm.floor.f32", ft);
    LLVMValueRef args[1] = { v };
    LLVMValueRef floored = LLVMBuildCall2(Bld, ft, floor_fn, args, 1, "fl");
    x->mode = Reg;
    x->type = intType;
    x->orig_type = intType;
    x->backend = LLVMBuildFPToSI(Bld, floored, Ty_i32, "floor");
}
void ORG_Float(ORG_Item *x) {
    LLVMValueRef v = LoadItem(x);
    x->mode = Reg;
    x->type = realType;
    x->orig_type = realType;
    x->backend = LLVMBuildSIToFP(Bld, v, Ty_float, "flt");
}
void ORG_Ord(ORG_Item *x) {
    LLVMValueRef v = LoadItem(x);
    LLVMTypeRef vt = LLVMTypeOf(v);
    if (vt != Ty_i32) {
        if (LLVMGetTypeKind(vt) == LLVMIntegerTypeKind) {
            unsigned w = LLVMGetIntTypeWidth(vt);
            if (w < 32) v = LLVMBuildZExt(Bld, v, Ty_i32, "ord");
            else if (w > 32) v = LLVMBuildTrunc(Bld, v, Ty_i32, "ord");
        }
    }
    x->mode = Reg;
    x->type = intType;
    x->orig_type = intType;
    x->backend = v;
}
void ORG_Len(ORG_Item *x) {
    if (x->type && x->type->form == ORB_Array && x->type->len < 0 && x->backend2) {
        // Open array — backend2 holds the runtime length.
        LLVMValueRef len_val = (LLVMValueRef)x->backend2;
        x->mode = Reg;
        x->type = intType;
        x->orig_type = intType;
        x->backend = len_val;
        x->backend2 = NULL;
        return;
    }
    LONGINT len = 0;
    if (x->type && x->type->len > 0) len = x->type->len;
    x->mode = ORB_Const;
    x->type = intType;
    x->orig_type = intType;
    x->a = len;
    x->backend = NULL;
    x->backend2 = NULL;
}
void ORG_Shift(LONGINT fct, ORG_Item *x, ORG_Item *y) {
    LLVMValueRef a = LoadItem(x), b = LoadItem(y);
    LLVMTypeRef at = LLVMTypeOf(a);
    /* fshl requires all three operands to share a type; coerce shift count. */
    if (LLVMTypeOf(b) != at) {
        unsigned aw = LLVMGetIntTypeWidth(at);
        unsigned bw = LLVMGetIntTypeWidth(LLVMTypeOf(b));
        if (bw < aw)      b = LLVMBuildZExt(Bld, b, at, "shx");
        else if (bw > aw) b = LLVMBuildTrunc(Bld, b, at, "shx");
    }
    x->mode = Reg;
    if (fct == 0) {                /* ASL — arithmetic shift left */
        x->backend = LLVMBuildShl(Bld, a, b, "shl");
    } else if (fct == 1) {         /* LSR — logical shift right */
        x->backend = LLVMBuildLShr(Bld, a, b, "lshr");
    } else {                       /* ROL — rotate left, via llvm.fshl.iN */
        unsigned w = LLVMGetIntTypeWidth(at);
        char nm[32];
        snprintf(nm, sizeof(nm), "llvm.fshl.i%u", w);
        LLVMTypeRef pt[3] = { at, at, at };
        LLVMTypeRef ft = LLVMFunctionType(at, pt, 3, 0);
        LLVMValueRef fn = LLVMGetNamedFunction(Mod, nm);
        if (!fn) fn = LLVMAddFunction(Mod, nm, ft);
        LLVMValueRef args[3] = { a, a, b };
        x->backend = LLVMBuildCall2(Bld, ft, fn, args, 3, "rol");
    }
}
void ORG_Bitwise(LONGINT fct, ORG_Item *x, ORG_Item *y) {
    LLVMValueRef a = LoadItem(x), b = LoadItem(y);
    coerce_pair(x, y, &a, &b);
    x->mode = Reg;
    if (fct == 0)      x->backend = LLVMBuildAnd(Bld, a, b, "band");
    else if (fct == 1) x->backend = LLVMBuildOr (Bld, a, b, "bor");
    else               x->backend = LLVMBuildXor(Bld, a, b, "bxor");
}
void ORG_UML(ORG_Item *x, ORG_Item *y) {
    LLVMValueRef a = LoadItem(x), b = LoadItem(y);
    if (LLVMTypeOf(b) != LLVMTypeOf(a)) {
        b = LLVMBuildIntCast2(Bld, b, LLVMTypeOf(a), 0, "umlx");
    }
    x->mode = Reg;
    x->backend = LLVMBuildMul(Bld, a, b, "uml");
}
void ORG_Bit(ORG_Item *x, ORG_Item *y) {
    LLVMValueRef a = LoadItem(x), b = LoadItem(y);
    LLVMValueRef sh = LLVMBuildLShr(Bld, a, b, "bsh");
    LLVMValueRef m  = LLVMBuildAnd(Bld, sh, LLVMConstInt(Ty_i32, 1, 0), "bm");
    x->mode = Cond;
    x->type = boolType;
    x->backend = LLVMBuildICmp(Bld, LLVMIntNE, m, LLVMConstInt(Ty_i32, 0, 0), "bit");
}
void ORG_Adr(ORG_Item *x) {
    x->type = longType;
    x->orig_type = longType;
    x->mode = Reg;
    if (x->backend) {
        x->backend = LLVMBuildPtrToInt(Bld, (LLVMValueRef)x->backend, Ty_i64, "adr");
    } else {
        x->backend = LLVMConstInt(Ty_i64, 0, 0);
    }
}
// --- Module lifecycle ---
void ORG_Open(const char *modid, INTEGER v) {
    (void)v;
    ORG_pc = 0;
    ORG_varsize = 0;
    LabelCount = 0;
    CallTop = -1;

    if (!Ctx) {
        Ctx = LLVMContextCreate();
        Ty_i1   = LLVMInt1TypeInContext(Ctx);
        Ty_i8   = LLVMInt8TypeInContext(Ctx);
        Ty_i32  = LLVMInt32TypeInContext(Ctx);
        Ty_i64  = LLVMInt64TypeInContext(Ctx);
        Ty_float= LLVMFloatTypeInContext(Ctx);
        Ty_void = LLVMVoidTypeInContext(Ctx);
        Ty_ptr  = LLVMPointerTypeInContext(Ctx, 0);

        {
            LLVMTypeRef td_fields[] = {
                Ty_i64,                                  // size
                Ty_i32,                                  // ext_level
                Ty_i32,                                  // _pad
                LLVMArrayType2(Ty_ptr, TD_LEVELS),       // ancestors
            };
            Ty_TDPrefix = LLVMStructTypeInContext(Ctx, td_fields, 4, 0);
        }

        // One-shot host-target setup so each module carries the correct
        // triple/layout AND so we can emit a native .o object file without
        // an external `llc` invocation. PIC reloc model is needed for
        // dynamic-linker-friendly object files on darwin.
        LLVMInitializeNativeTarget();
        LLVMInitializeNativeAsmPrinter();
        HostTriple = LLVMGetDefaultTargetTriple();
        LLVMTargetRef tgt = NULL;
        char *err = NULL;
        if (HostTriple && LLVMGetTargetFromTriple(HostTriple, &tgt, &err) == 0 && tgt) {
            HostTM = LLVMCreateTargetMachine(
                tgt, HostTriple, "", "",
                LLVMCodeGenLevelDefault, LLVMRelocPIC, LLVMCodeModelDefault);
            if (HostTM) {
                LLVMTargetDataRef dl = LLVMCreateTargetDataLayout(HostTM);
                HostLayout = LLVMCopyStringRepOfTargetData(dl);
                LLVMDisposeTargetData(dl);
            }
        }
        if (err) LLVMDisposeMessage(err);
    }

    strncpy(ModName, modid ? modid : "module", sizeof(ModName) - 1);
    ModName[sizeof(ModName) - 1] = 0;
    Mod = LLVMModuleCreateWithNameInContext(ModName, Ctx);
    if (HostTriple) LLVMSetTarget(Mod, HostTriple);
    if (HostLayout) LLVMSetDataLayout(Mod, HostLayout);
    Bld = LLVMCreateBuilderInContext(Ctx);
    ModInit = NULL;
    CurFn = NULL;
}

void ORG_SetDataSize(LONGINT dc) {
    ORG_varsize = dc;
}

void ORG_Header(void) {
    // Module body becomes <modid>__init(). Structure:
    //
    //   entry:
    //     %was = load i1, ptr @<mod>__inited
    //     br i1 %was, label %init_done, label %init_do
    //   init_do:
    //     store i1 true, ptr @<mod>__inited
    //     call void @<imp1>__init()
    //     call void @<imp2>__init()
    //     ; ...module body emits here...
    //     br label %init_done    ; emitted by ORG_Close
    //   init_done:
    //     ret void               ; emitted by ORG_Close
    //
    // The guard makes the init idempotent — safe under diamond imports and
    // direct calls from a C runner.
    LLVMTypeRef ft = LLVMFunctionType(Ty_void, NULL, 0, 0);
    char name[200];
    snprintf(name, sizeof(name), "%s__init", ModName);
    ModInit = LLVMAddFunction(Mod, name, ft);
    LLVMSetLinkage(ModInit, LLVMExternalLinkage);

    LLVMBasicBlockRef entry  = LLVMAppendBasicBlockInContext(Ctx, ModInit, "entry");
    LLVMBasicBlockRef do_bb  = LLVMAppendBasicBlockInContext(Ctx, ModInit, "init_do");
    ModInitDoneBB            = LLVMAppendBasicBlockInContext(Ctx, ModInit, "init_done");

    // entry: guard
    LLVMPositionBuilderAtEnd(Bld, entry);
    char gname[200];
    snprintf(gname, sizeof(gname), "%s__inited", ModName);
    LLVMValueRef guard = LLVMAddGlobal(Mod, Ty_i1, gname);
    LLVMSetInitializer(guard, LLVMConstInt(Ty_i1, 0, 0));
    LLVMSetLinkage(guard, LLVMInternalLinkage);
    LLVMValueRef was = LLVMBuildLoad2(Bld, Ty_i1, guard, "was_inited");
    LLVMBuildCondBr(Bld, was, ModInitDoneBB, do_bb);

    // init_do: set guard, call imports' init, then leave builder positioned
    // here for the module body to emit into.
    LLVMPositionBuilderAtEnd(Bld, do_bb);
    LLVMBuildStore(Bld, LLVMConstInt(Ty_i1, 1, 0), guard);

    LLVMTypeRef init_ty = LLVMFunctionType(Ty_void, NULL, 0, 0);
    for (ObjectPtr o = topScope ? topScope->next : NULL; o; o = o->next) {
        if (o->class != ORB_Mod) continue;
        const char *iname = ((ModulePtr)o)->orgname;
        if (strcmp(iname, "SYSTEM") == 0) continue;
        char init_name[200];
        snprintf(init_name, sizeof(init_name), "%s__init", iname);
        LLVMValueRef ifn = LLVMGetNamedFunction(Mod, init_name);
        if (!ifn) ifn = LLVMAddFunction(Mod, init_name, init_ty);
        LLVMBuildCall2(Bld, init_ty, ifn, NULL, 0, "");
    }

    // Force-emit every module-level VAR even if no procedure body
    // references it. Without this, an exported VAR that's only manipulated
    // by a (C) runtime override never appears in the .o file.
    for (ObjectPtr o = topScope ? topScope->next : NULL; o; o = o->next) {
        if (o->class == ORB_Var && o->lev == 0) ensure_global(o);
    }

    CurFn = ModInit;
    // Module-body statements start here; import-init calls don't count.
    EmittedStmts = 0;
}

// Emit a `<modid>__exports` global: a NULL-terminated array of
// { ptr name, ptr fn } records — one entry per exported procedure. The
// runtime test framework / Modules.ExportCount-and-friends walk this so a
// loaded plugin can be introspected without parsing Mach-O symtabs.
static void emit_exports_table(const char *modid) {
    LLVMTypeRef pair_t = LLVMStructTypeInContext(
        Ctx, (LLVMTypeRef[]){Ty_ptr, Ty_ptr}, 2, 0);

    LLVMValueRef *entries = NULL;
    int count = 0, cap = 0;
    char sym[200];

    for (ObjectPtr o = topScope ? topScope->next : NULL; o; o = o->next) {
        if (!o->expo) continue;
        if (o->class != ORB_Const) continue;
        if (!o->type || o->type->form != ORB_Proc) continue;

        snprintf(sym, sizeof(sym), "%s__%s", modid, o->name);
        LLVMValueRef fn = LLVMGetNamedFunction(Mod, sym);
        if (!fn) continue;

        size_t slen = strlen(o->name);
        LLVMValueRef nstr = LLVMConstStringInContext(Ctx, o->name,
                                                     (unsigned)slen, 0);
        LLVMTypeRef nstr_t = LLVMArrayType2(Ty_i8, (unsigned)slen + 1);
        char gname[256];
        snprintf(gname, sizeof(gname), ".str.exp.%s.%s", modid, o->name);
        LLVMValueRef ng = LLVMAddGlobal(Mod, nstr_t, gname);
        LLVMSetLinkage(ng, LLVMPrivateLinkage);
        LLVMSetGlobalConstant(ng, 1);
        LLVMSetInitializer(ng, nstr);

        LLVMValueRef pair_vals[2] = { ng, fn };
        LLVMValueRef pair = LLVMConstNamedStruct(pair_t, pair_vals, 2);

        if (count == cap) { cap = cap ? cap * 2 : 8;
                            entries = realloc(entries, cap * sizeof(*entries)); }
        entries[count++] = pair;
    }

    /* NULL-terminator entry */
    LLVMValueRef nulls[2] = { LLVMConstNull(Ty_ptr), LLVMConstNull(Ty_ptr) };
    LLVMValueRef term = LLVMConstNamedStruct(pair_t, nulls, 2);
    if (count == cap) { cap = cap + 1;
                        entries = realloc(entries, cap * sizeof(*entries)); }
    entries[count++] = term;

    LLVMTypeRef arr_t = LLVMArrayType2(pair_t, (unsigned)count);
    LLVMValueRef arr_init = LLVMConstArray2(pair_t, entries, (uint64_t)count);
    snprintf(sym, sizeof(sym), "%s__exports", modid);
    LLVMValueRef g = LLVMAddGlobal(Mod, arr_t, sym);
    LLVMSetGlobalConstant(g, 1);
    LLVMSetInitializer(g, arr_init);
    free(entries);
}

void ORG_Close(Ident modid, LONGINT key, LONGINT nofent) {
    (void)key; (void)nofent;

    if (!ModInit) {
        // Defensive: ORG_Header wasn't reached (parse error path).
        LLVMTypeRef ft = LLVMFunctionType(Ty_void, NULL, 0, 0);
        char name[200];
        snprintf(name, sizeof(name), "%s__init", modid);
        ModInit = LLVMAddFunction(Mod, name, ft);
        LLVMBasicBlockRef bb = LLVMAppendBasicBlockInContext(Ctx, ModInit, "entry");
        LLVMPositionBuilderAtEnd(Bld, bb);
        LLVMBuildRetVoid(Bld);
    } else {
        // End-of-body falls through to init_done; init_done returns.
        if (!current_block_terminated()) {
            LLVMBuildBr(Bld, ModInitDoneBB);
        }
        LLVMPositionBuilderAtEnd(Bld, ModInitDoneBB);
        LLVMBuildRetVoid(Bld);

        // If the module body emitted no user statements, treat the init
        // function as a stub too — same rationale as procedures: lets a C
        // runtime supply a strong override (e.g. for runtime modules whose
        // initialization is in the C glue).
        if (EmittedStmts == 0) {
            LLVMSetLinkage(ModInit, LLVMWeakAnyLinkage);
        }
    }

    /* Emit the runtime-introspectable exports table for this module. */
    emit_exports_table(modid);

    // Verify
    char *err = NULL;
    if (LLVMVerifyModule(Mod, LLVMReturnStatusAction, &err)) {
        fprintf(stderr, "LLVM verification failed for %s:\n%s\n", modid, err ? err : "");
    }
    if (err) LLVMDisposeMessage(err);

    // Write a side-channel <modid>.deps file listing direct imports so
    // the auto-link mode can compute transitive closure later. SYSTEM is
    // skipped — it's a compiler-internal pseudo-module with no .ll file.
    {
        char dpath[512];
        MakeFileName(dpath, modid, ".deps");
        FILE *df = fopen(dpath, "w");
        if (df) {
            for (ObjectPtr o = topScope ? topScope->next : NULL; o; o = o->next) {
                if (o->class != ORB_Mod) continue;
                const char *iname = ((ModulePtr)o)->orgname;
                if (strcmp(iname, "SYSTEM") == 0) continue;
                fprintf(df, "%s\n", iname);
            }
            fclose(df);
        }
    }

    // Write <modid>.ll (textual IR — kept for debugging / inspection).
    if (EmitLL) {
        char path[512];
        MakeFileName(path, modid, ".ll");
        char *err2 = NULL;
        if (LLVMPrintModuleToFile(Mod, path, &err2) != 0) {
            fprintf(stderr, "Failed to write %s: %s\n", path, err2 ? err2 : "");
        }
        if (err2) LLVMDisposeMessage(err2);
    }

    // Emit native object code directly so the linker step doesn't need to
    // re-run LLVM's IR backend on each .ll file.
    if (EmitObj && HostTM) {
        char opath[512];
        MakeFileName(opath, modid, ".o");
        char *err3 = NULL;
        if (LLVMTargetMachineEmitToFile(HostTM, Mod, opath,
                                        LLVMObjectFile, &err3) != 0) {
            fprintf(stderr, "Failed to emit %s: %s\n", opath, err3 ? err3 : "");
        }
        if (err3) LLVMDisposeMessage(err3);
    }

    // Tear down
    LLVMDisposeBuilder(Bld);
    LLVMDisposeModule(Mod);
    Bld = NULL; Mod = NULL; ModInit = NULL; CurFn = NULL; ModInitDoneBB = NULL;
}

void ORG_CheckRegs(void) {}

void ORG_Init(void) {
    ORG_pc = 0;
    ORG_varsize = 0;
    LabelCount = 0;
    CallTop = -1;
    Ctx = NULL;
}
