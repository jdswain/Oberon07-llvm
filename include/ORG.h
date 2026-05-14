/*
 * OC - Oberon Compiler for 65C816
 * Copyright (C) 2024-2026 Jason Swain
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

// ORG.h - Header file for Oberon RISC Code Generator

#ifndef ORG_H
#define ORG_H

#include <stdint.h>
#include "ORB.h"  // For ORB_Type, ORB_Object
#include "ORS.h"  // For ORS_Ident
#include "Oberon.h"

#define WordSize 4     // LLVM target word size in bytes (32-bit INTEGER)
extern LONGINT ORG_pc;
extern LONGINT ORG_varsize; // Size of module variables

// Type definitions
typedef struct {
    INTEGER mode;
    ORB_Type *type;
    LONGINT a, b, r;
    BOOLEAN rdo;  // read only
    ORB_Type *orig_type;  // Original operand type for signed comparisons
    void *backend;        // codegen-private: LLVMValueRef of address or value
    void *backend2;       // codegen-private: open-array length / aux value
} ORG_Item;

// Global variables
extern LONGINT ORG_pc;

// Item creation functions
void ORG_MakeConstItem(ORG_Item *x, ORB_Type *typ, LONGINT val);
void ORG_MakeRealItem(ORG_Item *x, REAL val);
void ORG_MakeStringItem(ORG_Item *x, LONGINT len);
void ORG_MakeDataItem(ORG_Item *x, ORB_Type *typ, LONGINT offset, LONGINT size);
LONGINT ORG_StrOffset(void);
void ORG_PutByte(int b);
void ORG_MakeItem(ORG_Item *x, ORB_Object *y, LONGINT curlev);

// Selector operations
void ORG_Field(ORG_Item *x, ORB_Object *y);
void ORG_Index(ORG_Item *x, ORG_Item *y);
void ORG_DeRef(ORG_Item *x);

// Type operations
void ORG_BuildTD(ORB_Type *T, LONGINT *dc);
void ORG_TypeTest(ORG_Item *x, ORB_Type *T, BOOLEAN varpar, BOOLEAN isguard);

// Boolean operations
void ORG_Not(ORG_Item *x);
void ORG_And1(ORG_Item *x);
void ORG_And2(ORG_Item *x, ORG_Item *y);
void ORG_Or1(ORG_Item *x);
void ORG_Or2(ORG_Item *x, ORG_Item *y);

// Arithmetic operations
void ORG_Neg(ORG_Item *x);
void ORG_AddOp(LONGINT op, ORG_Item *x, ORG_Item *y);
void ORG_MulOp(ORG_Item *x, ORG_Item *y);
void ORG_DivOp(LONGINT op, ORG_Item *x, ORG_Item *y);
void ORG_RealOp(INTEGER op, ORG_Item *x, ORG_Item *y);

// Set operations
void ORG_Singleton(ORG_Item *x);
void ORG_Set(ORG_Item *x, ORG_Item *y);
void ORG_In(ORG_Item *x, ORG_Item *y);
void ORG_SetOp(LONGINT op, ORG_Item *x, ORG_Item *y);

// Relation operations
void ORG_IntRelation(INTEGER op, ORG_Item *x, ORG_Item *y);
void ORG_RealRelation(INTEGER op, ORG_Item *x, ORG_Item *y);
void ORG_StringRelation(INTEGER op, ORG_Item *x, ORG_Item *y);

// Assignment operations
void ORG_StrToChar(ORG_Item *x);
void ORG_Store(ORG_Item *x, ORG_Item *y);
void ORG_StoreStruct(ORG_Item *x, ORG_Item *y);
void ORG_CopyString(ORG_Item *x, ORG_Item *y);

// Parameter operations
void ORG_OpenArrayParam(ORG_Item *x);
void ORG_VarParam(ORG_Item *x, ORB_Type *ftype);
void ORG_ValueParam(ORG_Item *x);
void ORG_StringParam(ORG_Item *x);

// For statement operations
void ORG_For0(ORG_Item *x, ORG_Item *y);
void ORG_For1(ORG_Item *x, ORG_Item *y, ORG_Item *z, ORG_Item *w, LONGINT *L);
void ORG_For2(ORG_Item *x, ORG_Item *y, ORG_Item *w);

// Case statement operations
void ORG_CaseLabel(ORG_Item *x, LONGINT val, LONGINT *chain);
void ORG_CaseRange(ORG_Item *x, LONGINT lo, LONGINT hi, LONGINT *chain);

// Branch and jump operations
LONGINT ORG_Here(void);
void ORG_FJump(LONGINT *L);
void ORG_CFJump(ORG_Item *x);
void ORG_BJump(LONGINT L);
void ORG_CBJump(ORG_Item *x, LONGINT L);
void ORG_Fixup(ORG_Item *x);
void ORG_FixOne(LONGINT at);
void ORG_FixLink(LONGINT L);

// Procedure call operations
void ORG_PrepCall(ORG_Item *x, LONGINT *r);
void ORG_Call(ORG_Item *x, LONGINT r);
void ORG_Enter(ORB_Object *proc, ORB_Object *params, LONGINT parblksize, LONGINT locblksize, BOOLEAN int_proc);
void ORG_Return(ORB_Object *proc, ORG_Item *x);

// Inline procedures
void ORG_Increment(LONGINT upordown, ORG_Item *x, ORG_Item *y);
void ORG_Include(LONGINT inorex, ORG_Item *x, ORG_Item *y);
void ORG_Assert(ORG_Item *x);
void ORG_New(ORG_Item *x);
void ORG_Pack(ORG_Item *x, ORG_Item *y);
void ORG_Unpk(ORG_Item *x, ORG_Item *y);
void ORG_Get(ORG_Item *addr, ORG_Item *var);
void ORG_Put(ORG_Item *addr, ORG_Item *val);
void ORG_Copy(ORG_Item *x, ORG_Item *y, ORG_Item *z);

// Inline functions
void ORG_Abs(ORG_Item *x);
void ORG_Odd(ORG_Item *x);
void ORG_Floor(ORG_Item *x);
void ORG_Float(ORG_Item *x);
void ORG_Ord(ORG_Item *x);
void ORG_Len(ORG_Item *x);
void ORG_Shift(LONGINT fct, ORG_Item *x, ORG_Item *y);
void ORG_Bitwise(LONGINT fct, ORG_Item *x, ORG_Item *y);
void ORG_UML(ORG_Item *x, ORG_Item *y);
void ORG_Bit(ORG_Item *x, ORG_Item *y);
void ORG_Adr(ORG_Item *x);
void ORG_Snapshot(ORG_Item *x);
void ORG_SetTargetTriple(const char *triple);

// Module management functions
void ORG_Open(const char *modid, INTEGER v);
void ORG_SetDataSize(LONGINT dc);
void ORG_Header(void);
void ORG_Close(Ident modid, LONGINT key, LONGINT nofent);
void ORG_CheckRegs(void);

// Module initialization
void ORG_Init(void);

// Driver-controlled emission flags. Set before each ORP_Compile.
//   emit_ll = TRUE: write <modid>.ll alongside the .smb file (default)
//   emit_obj = TRUE: emit a native <modid>.o object file (default)
// `-S` clears emit_obj; both can be cleared together for "syntax-check-only" runs.
void ORG_SetEmitFlags(BOOLEAN emit_ll, BOOLEAN emit_obj);

#endif // ORG_H
