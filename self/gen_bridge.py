#!/usr/bin/env python3
"""Generate self/ORG_rt.c and self/main.c from the C compiler sources.

ORG_rt.c = src/ORG.c with:
  - the ORG.h/ORS.h/ORB.h includes replaced by a self-contained prelude:
    mirror structs for the Oberon-side ORB records and ORG.Item (with the
    {tag, refcount} ARC header the self-hosted compiler emits), extern
    declarations for the Oberon module globals, and shims for ORS.Mark /
    MakeFileName;
  - every procedure exported through self/ORG.Mod renamed ORG_X -> ORG__X
    (the Oberon-mangled name), so the strong C definitions override the
    weak Oberon stubs at link time;
  - open-array parameters (Open/Close modid) taking the Oberon (ptr, len)
    ABI.

main.c = the driver part of src/ORP.c (arg parsing, auto-compile of
stale imports, linking) with frontend calls redirected to the Oberon
modules' mangled entry points.

Regenerate after changing src/ORG.c or the driver:  python3 gen_bridge.py
"""
import re, pathlib

SRC = pathlib.Path("../src")
ORG = (SRC / "ORG.c").read_text()
ORP = (SRC / "ORP.c").read_text()

# ---------------------------------------------------------------- ORG_rt.c

PRELUDE = r'''/*
 * ORG_rt.c — LLVM backend for the self-hosted Oberon compiler.
 * GENERATED from src/ORG.c by gen_bridge.py — edit that and regenerate.
 *
 * The frontend (ORS/ORB/ORP) is Oberon, compiled by this same compiler;
 * this file provides the strong definitions for self/ORG.Mod's weak
 * stubs and reads the Oberon symbol-table records through mirror structs.
 * Every mirror starts with the {tag, refcount} header the Oberon side's
 * records carry. Field order must match self/ORB.Mod and self/ORG.Mod.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>

#include <llvm-c/Core.h>
#include <llvm-c/Analysis.h>
#include <llvm-c/BitWriter.h>
#include <llvm-c/Target.h>
#include <llvm-c/TargetMachine.h>

typedef int32_t INTEGER;
typedef int64_t LONGINT;
typedef float   REAL;
typedef bool    BOOLEAN;
typedef char    Ident[32];
#define TRUE  true
#define FALSE false

/* class values (self/ORB.Mod) */
#define ORB_Head 0
#define ORB_Const 1
#define ORB_Var 2
#define ORB_Par 3
#define ORB_Fld 4
#define ORB_Typ 5
#define ORB_SProc 6
#define ORB_SFunc 7
#define ORB_Mod 8
#define ORB_Meth 9

/* form values */
#define ORB_Byte 1
#define ORB_Bool 2
#define ORB_Char 3
#define ORB_Int 4
#define ORB_Real 5
#define ORB_Set 6
#define ORB_Pointer 7
#define ORB_NilTyp 8
#define ORB_NoTyp 9
#define ORB_Proc 10
#define ORB_String 11
#define ORB_Array 12
#define ORB_Record 13
#define ORB_Intfc 14

/* scanner token values used by the backend */
#define ORS_times 1
#define ORS_rdiv 2
#define ORS_div 3
#define ORS_mod 4
#define ORS_plus 6
#define ORS_minus 7
#define ORS_eql 9
#define ORS_neq 10
#define ORS_lss 11
#define ORS_geq 12
#define ORS_leq 13
#define ORS_gtr 14

/* --- mirrors of the Oberon records (with ARC header) --- */

typedef struct ORB_Object ORB_Object;
typedef struct ORB_Type   ORB_Type;
typedef struct ORB_Impl   ORB_Impl;
typedef ORB_Object *ObjectPtr;
typedef ORB_Type   *TypePtr;

struct ORB_Object {          /* self/ORB.Mod ObjectDesc */
    void   *_tag; int64_t _rc;
    INTEGER class, exno;
    bool    expo, rdo;
    INTEGER lev;
    ORB_Object *next, *dsc;
    ORB_Type   *type;
    Ident   name;
    LONGINT val;
    bool    initf;
    char    mname[104];
    void   *backend, *backend2;
};

typedef struct {             /* self/ORB.Mod ModDesc (extends ObjectDesc) */
    ORB_Object base;
    Ident orgname;
} ORB_Module;
typedef ORB_Module *ModulePtr;

struct ORB_Type {            /* self/ORB.Mod TypeDesc */
    void   *_tag; int64_t _rc;
    INTEGER form, ref, mno, nofpar, len;
    ORB_Object *dsc, *typobj;
    ORB_Type   *base;
    INTEGER size;
    bool    weak;
    ORB_Object *meth;
    ORB_Impl   *impl;
    INTEGER nofmeth;
    bool    mfixed, mthd;
    void   *backend, *backend2;
};

struct ORB_Impl {            /* self/ORB.Mod ImplDesc */
    void *_tag; int64_t _rc;
    ORB_Type *intfc;
    ORB_Impl *next;
};

typedef struct {             /* self/ORG.Mod Item */
    void   *_tag; int64_t _rc;
    INTEGER mode;
    ORB_Type *type;
    LONGINT a, b, r;
    bool    rdo;
    ORB_Type *orig_type;
    void   *backend, *backend2;
} ORG_Item;

/* --- Oberon module globals (mangled names) --- */
extern ORB_Object *ORB__topScope;
extern ORB_Type *ORB__byteType, *ORB__boolType, *ORB__charType;
extern ORB_Type *ORB__intType, *ORB__longType, *ORB__realType;
extern ORB_Type *ORB__setType, *ORB__nilType, *ORB__noType, *ORB__strType;
#define topScope ORB__topScope
#define byteType ORB__byteType
#define boolType ORB__boolType
#define charType ORB__charType
#define intType  ORB__intType
#define longType ORB__longType
#define realType ORB__realType
#define setType  ORB__setType
#define strType  ORB__strType

extern char    ORS__str[256];
extern LONGINT ORS__slen;
#define ORS_str  ORS__str
#define ORS_slen ORS__slen

extern void ORS__Mark(const char *msg, INTEGER len);
static void ORS_Mark(const char *msg) {
    ORS__Mark(msg, (INTEGER)strlen(msg) + 1);
}

/* --- local reimplementations of the ORB helpers the backend needs --- */

static int ORB_TotalMeths(ORB_Type *rec) {
    int n = 0;
    while (rec) { if (rec->nofmeth > n) n = rec->nofmeth; rec = rec->base; }
    return n;
}

static ORB_Object *ORB_FindMeth(ORB_Type *rec, const char *name) {
    while (rec) {
        for (ORB_Object *m = rec->meth; m; m = m->next) {
            if (!m->initf && strcmp(m->name, name) == 0) return m;
        }
        rec = rec->base;
    }
    return NULL;
}

/* Output-path handling: the driver tells us the source directory; the
 * Oberon ORB keeps its own copy for .smb paths. */
static char org_source_dir[256];
void ORG_SetSourceDir(const char *dir) {
    strncpy(org_source_dir, dir ? dir : "", sizeof(org_source_dir) - 1);
    org_source_dir[sizeof(org_source_dir) - 1] = 0;
}
static void MakeFileName(char *FName, const char *name, const char *ext) {
    snprintf(FName, 256, "%s%s%s", org_source_dir, name, ext);
}

/* ================= generated from src/ORG.c below ================= */

'''

# strip everything up to and including the local includes
body = ORG
m = re.search(r'#include "ORB.h"\n', body)
body = body[m.end():]

# exported procedures (must track self/ORG.Mod)
names = """MakeConstItem MakeRealItem MakeStringItem MakeItem StrOffset PutByte
Field Index DeRef MethodItem InitItem IfaceMethodItem Discard PtrToIface
StoreIface IfaceRelation BuildTD TypeTest Not And1 And2 Or1 Or2 Neg AddOp
MulOp DivOp RealOp Singleton Set In SetOp IntRelation RealRelation
StringRelation StrToChar Store StoreStruct CopyString OpenArrayParam
VarParam ValueParam StringParam For0 For1 For2 Snapshot CaseLabel CaseRange
Here FJump CFJump BJump CBJump Fixup FixOne FixLink PrepCall Call Enter
Return Increment Include Assert New Pack Unpk Get Put Copy Abs Odd Floor
Float Ord Len Shift Bitwise UML Bit Adr Open SetDataSize Header Close
CheckRegs Init""".split()
for n in names:
    body = re.sub(r'\bORG_%s\b' % n, 'ORG__%s' % n, body)

# open-array ABI for the module-name parameters
body = body.replace(
    "void ORG__Open(const char *modid, INTEGER v) {",
    "void ORG__Open(const char *modid, INTEGER modid_len, INTEGER v) {\n    (void)modid_len;")
body = body.replace(
    "void ORG__Close(Ident modid, LONGINT key, LONGINT nofent) {",
    "void ORG__Close(const char *modid, INTEGER modid_len, LONGINT key, LONGINT nofent) {\n    (void)modid_len;")

# mname is an embedded array in the mirror, not a pointer
body = body.replace(
    "if (proc->class == ORB_Meth && proc->mname) {",
    "if (proc->class == ORB_Meth && proc->mname[0]) {")

# ORG_pc / ORG_varsize stay C-internal
out = PRELUDE + body
pathlib.Path("ORG_rt.c").write_text(out)
print("ORG_rt.c: %d lines" % out.count("\n"))

# ---------------------------------------------------------------- main.c

lines = ORP.splitlines(keepends=True)
# driver block: from the RuntimeDir comment to EOF
start = next(i for i, l in enumerate(lines) if "Resolved at startup" in l)
driver = "".join(lines[start:])

MAIN_PRELUDE = r'''/*
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

'''

# patch the extracted driver
driver = driver.replace('#include "ORP.h"', '')

# main(): replace frontend init + compile sequence
driver = driver.replace(
    """    Texts_OpenWriter(&W);
    Texts_WriteString(&W, "Oberon LLVM Compiler  Version ");
    Texts_WriteInt(&W, VERSION, 1);
    Texts_WriteLn(&W);
    Texts_Append(Oberon_Log, W.buf);
    Texts_ClearWriter(&W);

    ORB_Initialize();
    ORB_Init();

    dummy = (ORB_Object*)calloc(1, sizeof(ORB_Object));
    dummy->class = ORB_Var;
    dummy->type = intType;

    expression = expression0;
    Type = Type0;
    FormalType = FormalType0;

    ORG_Init();
    ORG_SetEmitFlags(TRUE, emit_obj);
    ORP_Compile(filename, forceNewSF);

    if (ORS_errcnt > 0) {""",
    """    printf("Oberon LLVM Compiler (self-hosted)\\n");

    ORP__init();   /* runs the Oberon module init chain */
    ORG_SetEmitFlags(TRUE, emit_obj);
    derive_source_dir(filename, main_source_dir, sizeof(main_source_dir));
    ORG_SetSourceDir(main_source_dir);
    ORP__Compile(filename, (INTEGER)strlen(filename) + 1, forceNewSF);

    if (ORS__errcnt > 0) {""")

# the failure-path printf after the compile still names the C global
driver = driver.replace(
    'printf("Compilation failed with %d errors\\n", ORS_errcnt);',
    'printf("Compilation failed with %d errors\\n", ORS__errcnt);')

assert "ORP__Compile" in driver, "main() compile sequence not patched"

out = MAIN_PRELUDE + driver
pathlib.Path("main.c").write_text(out)
print("main.c: %d lines" % out.count("\n"))
