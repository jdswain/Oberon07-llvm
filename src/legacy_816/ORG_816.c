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

// ORG.c - Code generator for Oberon compiler for RISC processor
// Translated from ORG.Mod by N.Wirth

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include "ORG.h"
#include "ORS.h"
#include "ORB.h"
#include "Files.h"
#include "codegen.h"

// Constants
#define CODE_ORG 0x0000         // Code starts at $0000 (must match codegen.c)
#define MT 15                   // Max 15 general regs (R0-R14)
#define SB 15                   // Static Base is R15
#define maxStrx 16000
#define maxTD 160

// 65C816 register scheme
// - use first 16 bytes of direct page as 8 registers
// - use R8 as StaticBase

#define REG_SIZE 2  // 16-bit registers
#define SB_DP 0x00  // SB lives at DP $00-$01

static LONGINT reg_addr(int reg) {
    return reg * REG_SIZE + 2;  // R[0]=$02, R[1]=$04, ... R[14]=$1E
}

// Internal item modes
#define Reg 10
#define RegI 11
#define Cond 12

// Condition codes (Inverted are 8 different)
#define MI 0
#define PL 8
#define EQ 1
#define NE 9
#define LT 5
#define GE 13
#define LE 6
#define GT 14
#define AL 7
#define NV 15

// Global variables
LONGINT ORG_pc, ORG_varsize;
static LONGINT tdx, strx;
static LONGINT entry;
static LONGINT RH;
static LONGINT frame;
static LONGINT fixorgP, fixorgD, fixorgT;
static BOOLEAN check;
static INTEGER version;
static INTEGER relmap[6];
uint8_t code[maxCode];
static uint16_t data[maxTD];
static char str[maxStrx];
static uint16_t td_fixup[maxTD][2];  // [byte_offset_of_lo_word, mno]
static int td_fixupC = 0;

// Forward declarations
static int load(ORG_Item *x);
static void loadAdr(ORG_Item *x);
static LONGINT ORG_log2(LONGINT m, LONGINT *e);
static void patch(LONGINT branchOperandAddr);
static LONGINT emitFwdBranch(OpCode op);

static void Set16(int a, int i) {
  int new_longa = (a?1:longa);
  int new_longi = (i?1:longi);
  if ((longa == new_longa) && (longi == new_longi)) return;
  int val = (a?0x20:0x00) + (i?0x10:0x00);
  longa = new_longa;
  longi = new_longi;
  codegen_gen(sREP, Immediate, val, 0); 
}

static void Set8(int a, int i) {
  int new_longa = (a?0:longa);
  int new_longi = (i?0:longi);
  if ((longa == new_longa) && (longi == new_longi)) return;
  int val = (a?0x20:0x00) + (i?0x10:0x00);
  longa = new_longa;
  longi = new_longi;
  codegen_gen(sSEP, Immediate, val, 0); 
}

static void incR(void) {
    if (RH < MT - 1) {
        RH++;
    } else {
        ORS_Mark("register stack overflow");
    }
}

#define SB_TEMP 0x20  // Temp DP location for imported module's var_base (above SB at $1E)
#define SB_TEMP_BANK 0x22  // Temp DP location for imported module's bank byte
#define BANK_DP 0x44  // Own module's data bank byte (set at module entry)

// FP workspace DP addresses ($22-$41)
#define FP_A_LO  0x22  // operand A / result low word
#define FP_A_HI  0x24  // operand A / result high word
#define FP_B_LO  0x26  // operand B low word
#define FP_B_HI  0x28  // operand B high word
#define FP_SIGN  0x2A  // result sign
#define FP_EXP   0x2C  // working exponent
#define FP_M1_LO 0x2E  // mantissa 1 low (16 bits)
#define FP_M1_HI 0x30  // mantissa 1 high (8 bits in 16-bit word)
#define FP_M2_LO 0x32  // mantissa 2 low
#define FP_M2_HI 0x34  // mantissa 2 high
#define FP_PROD0 0x36  // product/temp word 0
#define FP_PROD1 0x38  // product/temp word 1
#define FP_PROD2 0x3A  // product/temp word 2
#define FP_TEMP  0x3C  // scratch
#define FP_TEMP2 0x3E  // scratch
#define FP_CNT   0x40  // loop counter

// FP operation indices
#define FP_ADD   0
#define FP_MUL   1
#define FP_DIV   2
#define FP_CMP   3
#define FP_FLOOR 4
#define FP_FLT   5
#define FP_OPS   6

#define maxFPFixups 64
static LONGINT fp_fixups[FP_OPS][maxFPFixups];
static int fp_fixup_count[FP_OPS];
static LONGINT fp_sub_addr[FP_OPS];

// Returns DP address of the correct module's var_base.
// mno >= 0 (own module): returns SB_DP ($00), no code emitted.
// mno < 0 (import): emits LDA #(-mno) / STA SB_TEMP with relocation.
static int GetSB(LONGINT mno) {
  if (mno >= 0) {
    return SB_DP;
  }
  Set16(1, 1);
  // Load imported module's var_base address
  reloc[relocC++] = ORG_pc;
  codegen_gen(sLDA, Immediate, (int)(-mno), 0);  // operand = mno for loader
  codegen_gen(sSTA, DirectPage, SB_TEMP, 0);
  // Load imported module's data bank
  reloc[relocC++] = ORG_pc | 0x80000000;              // bank reloc flag (bit 15)
  codegen_gen(sLDA, Immediate, (int)(-mno), 0);   // operand = mno for loader
  codegen_gen(sSTA, DirectPage, SB_TEMP_BANK, 0);
  return SB_TEMP;
}

void ORG_CheckRegs(void) {
  Set16(1, 1);  // We reset here as this is called at the end of every statement.
  // This is required because the start of any statement may be a branch target and we
  // need to ensure that if the statement needs to switch to 8-bit we always generate the SEP.
    if (RH != 0) {
        ORS_Mark("Reg Stack");
        RH = 0;
    }
    if (ORG_pc >= maxCode - 40) {
        ORS_Mark("program too long");									 
    }
    // 65C816: Disable frame checking for now - hardware stack management
    if (frame != 0) {
         ORS_Mark("frame error");
         frame = 0;
    }
}

static void SetCC(ORG_Item *x, LONGINT n) {
    // Store the original operand type for signed comparison logic
    x->orig_type = x->type;  // Store original operand type
    x->mode = Cond;
    x->a = 0;
    x->b = 0;
    x->r = n;
    // x->type will be changed to BOOLEAN by the parser, but we have the original in x->orig_type
}

static void Trap(LONGINT cond, LONGINT num) {
  // In future we can use this for exception exits, but for now...
  // It would be useful to print a stack trace
  // ToDo: Should this be signed maths?
  switch (cond) {
  case EQ:  // Branch if Equal (Zero flag set)
	codegen_gen(sBEQ, ProgramCounterRelative, ORG_pc + 4, 0);
	codegen_gen(sBRK, Immediate, num, 0);
	break;
  case NE:  // Branch if Not Equal (Zero flag clear)
	codegen_gen(sBNE, ProgramCounterRelative, ORG_pc + 4, 0);
	codegen_gen(sBRK, Immediate, num, 0);
	break;
  case MI:  // Branch if Minus (Negative flag set)
	codegen_gen(sBMI, ProgramCounterRelative, ORG_pc + 4, 0);
	codegen_gen(sBRK, Immediate, num, 0);
	break;
  case PL:  // Branch if Plus (Negative flag clear)
	codegen_gen(sBPL, ProgramCounterRelative, ORG_pc + 4, 0);
	codegen_gen(sBRK, Immediate, num, 0);
	break;
  case LT:  // Branch if Less Than - use BCC
	codegen_gen(sBCC, ProgramCounterRelative, ORG_pc + 4, 0);
	codegen_gen(sBRK, Immediate, num, 0);
	break;
  case GE:  // Branch if Greater or Equal - use BCS
	codegen_gen(sBCS, ProgramCounterRelative, ORG_pc + 4, 0);
	codegen_gen(sBRK, Immediate, num, 0);
	break;
  case LE:  // Branch if Less or Equal (also handles negated GT)
            // For negated GT: branch if NOT(A > B), which is A <= B
            // Check equality first, then use BCS for the < case
	codegen_gen(sBEQ, ProgramCounterRelative, ORG_pc + 4 + 4, 0);
	codegen_gen(sBCC, ProgramCounterRelative, ORG_pc + 4 + 2, 0);
	codegen_gen(sBRA, ProgramCounterRelative, ORG_pc + 4, 0);  // over
	codegen_gen(sBRK, Immediate, num, 0);
	break;
  case GT:  // Branch if Greater Than
	codegen_gen(sBEQ, ProgramCounterRelative, ORG_pc + 4 + 2, 0);
	codegen_gen(sBCS, ProgramCounterRelative, ORG_pc + 4, 0);
	codegen_gen(sBRK, Immediate, num, 0);
	break;
  case AL:
	codegen_gen(sBRK, Immediate, num, 0);
	break;
  case NV:
	// Never trap (e.g. ASSERT(TRUE)) — emit nothing
	break;
  default:
	ORS_Mark("Trap not implemented");
	break;
  }
}

static LONGINT negated(LONGINT cond) {
    switch (cond) {
        case EQ: return NE;   // 1 -> 9
        case NE: return EQ;   // 9 -> 1
        case LT: return GE;   // 5 -> 13
        case GE: return LT;   // 13 -> 5
        case LE: return GT;   // 6 -> 14
        case GT: return LE;   // 14 -> 6
        case MI: return PL;   // 0 -> 8
        case PL: return MI;   // 8 -> 0
        case AL: return NV;   // 7 -> 15
        case NV: return AL;   // 15 -> 7
        default: 
            printf("ERROR: Unknown condition code $%04X in negated()\n", cond);
            return cond;
    }
}

// Generate 65C816 branch instruction based on condition code
// target parameter is always a fixup chain link for forward branches
// (actual target will be resolved later by ORG_FixLink)
static void emitBranch(LONGINT cond, ORB_Type *type, AddrMode mode, LONGINT target) {
    switch (cond) {
        case EQ:  // Branch if Equal (Zero flag set)
            codegen_gen(sBNE, ProgramCounterRelative, ORG_pc + 2 + 3, 0);
            codegen_gen(sBRL, mode, target, 0);
            break;
        case NE:  // Branch if Not Equal (Zero flag clear)
            codegen_gen(sBEQ, ProgramCounterRelative, ORG_pc + 2 + 3, 0);
            codegen_gen(sBRL, mode, target, 0);
            break;
        case MI:  // Branch if Minus (Negative flag set)
            codegen_gen(sBPL, ProgramCounterRelative, ORG_pc + 2 + 3, 0);
            codegen_gen(sBRL, mode, target, 0);
            break;
        case PL:  // Branch if Plus (Negative flag clear)
            codegen_gen(sBMI, ProgramCounterRelative, ORG_pc + 2 + 3, 0);
            codegen_gen(sBRL, mode, target, 0);
            break;
        case LT:  // Branch if Less Than
            if (type->size == 2 && type->form == ORB_Int) {
                // Signed 16-bit comparison with single fixup point - INVERTED LOGIC
                // Branch to target when NOT greater or equal (condition is FALSE, i.e., less than)
                // Pattern: BVS INVERT; BMI TO_TARGET; BRA SKIP; INVERT: BPL TO_TARGET; BRA SKIP; TO_TARGET: BRA target; SKIP: ...
                
                codegen_gen(sBVS, ProgramCounterRelative, ORG_pc + 2 + 4, 0);  // BVS: if overflow, jump to INVERT
                codegen_gen(sBMI, ProgramCounterRelative, ORG_pc + 2 + 6, 0);  // BMI: if no overflow & negative, jump to TO_TARGET (less than)
                codegen_gen(sBRA, ProgramCounterRelative, ORG_pc + 2 + 7, 0);  // BRA: skip to SKIP (greater or equal)
                // INVERT section: overflow inverts meaning  
                codegen_gen(sBPL, ProgramCounterRelative, ORG_pc + 2 + 2, 0);  // BMI: if overflow & negative, jump to TO_TARGET (not less than)
                codegen_gen(sBRA, ProgramCounterRelative, ORG_pc + 2 + 3, 0);  // BRA: skip to SKIP (less than)
                // TO_TARGET: single fixup point
                codegen_gen(sBRL, mode, target, 0);                            // BRL target (single fixup)
                // SKIP: fall through when condition is TRUE (greater or equal)
            } else {
                // Unsigned comparison: branch when A < operand (carry clear after CMP)
                codegen_gen(sBCS, ProgramCounterRelative, ORG_pc + 2 + 3, 0);  // BCS skip (>= → don't branch)
                codegen_gen(sBRL, mode, target, 0);                            // BRL target (< → branch)
            }
            break;
        case GE:  // Branch if Greater or Equal
            if (type->size == 2 && type->form == ORB_Int) {
                // Signed 16-bit comparison with single fixup point - INVERTED LOGIC
                // Branch to target when NOT less than (condition is FALSE)
                // Pattern: BVS INVERT; BPL TO_TARGET; BRA SKIP; INVERT: BMI TO_TARGET; BRA SKIP; TO_TARGET: BRA target; SKIP: ...

                codegen_gen(sBVS, ProgramCounterRelative, ORG_pc + 2 + 4, 0);  // BVS: if overflow, jump to INVERT
                codegen_gen(sBPL, ProgramCounterRelative, ORG_pc + 2 + 6, 0);  // BPL: if no overflow & positive, jump to TO_TARGET (NOT less)
                codegen_gen(sBRA, ProgramCounterRelative, ORG_pc + 2 + 7, 0);  // BRA: skip to SKIP (is less than)
                // INVERT section: overflow inverts meaning
                codegen_gen(sBMI, ProgramCounterRelative, ORG_pc + 2 + 2, 0);  // BMI: if overflow & negative, jump to TO_TARGET (NOT less)
                codegen_gen(sBRA, ProgramCounterRelative, ORG_pc + 2 + 3, 0);  // BRA: skip to SKIP (is less than)
                // TO_TARGET: single fixup point
                codegen_gen(sBRL, mode, target, 0);                            // BRL target (single fixup)
                // SKIP: fall through when condition is TRUE (less than)
            } else {
                // Unsigned comparison: branch when A >= operand (carry set after CMP)
                codegen_gen(sBCC, ProgramCounterRelative, ORG_pc + 2 + 3, 0);  // BCC skip (< → don't branch)
                codegen_gen(sBRL, mode, target, 0);                            // BRL target (>= → branch)
            }
            break;
        case LE:  // Branch if Less or Equal
            if (type->size == 2 && type->form == ORB_Int) {
                // Signed 16-bit comparison: branch when x <= y (i.e., x-y <= 0)
                // If equal (Z=1), branch to target (equal IS less-or-equal)
                codegen_gen(sBEQ, ProgramCounterRelative, ORG_pc + 2 + 10, 0);  // BEQ to TO_TARGET (equal means LE)
                // Then check for greater using signed logic (same as GE but excluding equality)
                // For signed: if V=0: BPL=GT, BMI=LT; if V=1: BMI=GT, BPL=LT
                codegen_gen(sBVS, ProgramCounterRelative, ORG_pc + 2 + 4, 0);  // BVS: if overflow, jump to INVERT
                codegen_gen(sBMI, ProgramCounterRelative, ORG_pc + 2 + 6, 0);  // BMI: if no overflow & negative, jump to TO_TARGET (less than)
                codegen_gen(sBRA, ProgramCounterRelative, ORG_pc + 2 + 7, 0);  // BRA: skip to SKIP (greater or equal)
                // INVERT section: overflow inverts meaning
                codegen_gen(sBPL, ProgramCounterRelative, ORG_pc + 2 + 2, 0);  // BPL: if overflow & positive, jump to TO_TARGET (not less than)
                codegen_gen(sBRA, ProgramCounterRelative, ORG_pc + 2 + 3, 0);  // BRA: skip to SKIP (less than)
                // TO_TARGET: single fixup point
                codegen_gen(sBRL, mode, target, 0);                            // BRL target (single fixup)
            } else {
                // Unsigned comparison: branch when A <= operand (equal OR carry clear after CMP)
                codegen_gen(sBEQ, ProgramCounterRelative, ORG_pc + 2 + 2, 0);  // BEQ to BRL (= → branch)
                codegen_gen(sBCS, ProgramCounterRelative, ORG_pc + 2 + 3, 0);  // BCS skip (> → don't branch)
                codegen_gen(sBRL, mode, target, 0);                            // BRL target (<= → branch)
            }
            break;
        case GT:  // Branch if Greater Than
            if (type->size == 2 && type->form == ORB_Int) {
                // Signed 16-bit comparison with single fixup point - INVERTED LOGIC
                // Branch to target when NOT less or equal (condition is FALSE, i.e., greater than)
                // First check for equality (if equal, fall through - don't branch to target)
                codegen_gen(sBEQ, ProgramCounterRelative, ORG_pc + 2 + 13, 0);  // BEQ: skip all GT logic (fall through)
                // Then check for greater than using inverted signed logic
                codegen_gen(sBVS, ProgramCounterRelative, ORG_pc + 2 + 4, 0);  // BVS: if overflow, jump to INVERT
                codegen_gen(sBPL, ProgramCounterRelative, ORG_pc + 2 + 6, 0);  // BPL: if no overflow & positive, jump to TO_TARGET (greater)
                codegen_gen(sBRA, ProgramCounterRelative, ORG_pc + 2 + 7, 0);  // BRA: skip to SKIP (less or equal)
                // INVERT section: overflow inverts meaning  
                codegen_gen(sBMI, ProgramCounterRelative, ORG_pc + 2 + 2, 0);  // BPL: if overflow & positive result, jump to TO_TARGET (actual less, so GT is false)
                codegen_gen(sBRA, ProgramCounterRelative, ORG_pc + 2 + 3, 0);  // BRA: skip to SKIP (actual greater with overflow, so LE is false)
                // TO_TARGET: single fixup point
                codegen_gen(sBRL, mode, target, 0);                            // BRA target (single fixup)
                // SKIP: fall through when condition is TRUE (less or equal)
            } else {
                // Unsigned comparison
                // Check equality first, then use BCS for the < case
                codegen_gen(sBEQ, ProgramCounterRelative, ORG_pc + 2 + 4, 0);
                codegen_gen(sBCC, ProgramCounterRelative, ORG_pc + 2 + 2, 0);
                codegen_gen(sBRA, ProgramCounterRelative, ORG_pc + 2 + 3, 0);  // over
                codegen_gen(sBRL, mode, target, 0);
            }
            break;
        case AL:   // Always branch (unconditional)
            codegen_gen(sBRL, mode, target, 0);
            break;
        case NV:  // Never branch (nop - could optimize away)
            // Do nothing for "never" condition
            break;
        default:
            ORS_Mark("condition not implemented");
            break;
    }
}

static void fix(LONGINT at, LONGINT target) {
    // For 65C816: All fixup locations are BRL instructions (3 bytes: $82 + 2-byte offset)
    // 'at' is the address of the low byte of the 2-byte offset field
    // 'target' is the target address
    // For BRL: offset = target - (branch_addr + 3) = target - (at + 2)
    LONGINT offset = target - (at + 1);
    LONGINT code_index = at - CODE_ORG;  // Index for low byte of offset
    
    if ((offset >= -128) && (offset <= 127)) {
        // Optimize to BRA (1-byte offset) + NOP
        code[code_index-1] = 0x80;           // Change opcode from BRL to BRA
        code[code_index] = offset & 0xFF;    // Store 1-byte offset
        code[code_index+1] = 0xEA;           // NOP in the high byte position
    } else {
	  // Keep as BRL (2-byte offset)
	  offset -= 1; // Adjust for extra byte for BRL
	  code[code_index] = offset & 0xFF;    // Store low byte of offset
	  code[code_index+1] = offset >> 8;    // Store high byte of offset
    }
}

void ORG_FixOne(LONGINT at) {
    // For 65C816: fix a single forward branch
    // 'at' is the address of the offset byte
    // Target is current ORG_pc
    // Original Oberon: fix(at, pc-at-1)
    // For 65C816 branches: offset = target - (branch_addr + 2) = target - (at + 1)
    // So target = ORG_pc, and we want offset = ORG_pc - (at + 1) = ORG_pc - at - 1
    fix(at, ORG_pc);
}

void ORG_FixLink(LONGINT L) {
    // For 65C816: fix a chain of forward branches
    // L is the address of the offset byte of the most recent branch
    LONGINT L1;
	LONGINT code_index;

    while (L != 0) {
	  code_index = L - CODE_ORG;  // Index for low byte of offset
	  // Read the 2-byte chain link BEFORE fixing (fix() will overwrite it)
	  L1 = code[code_index] | (code[code_index + 1] << 8);

	  // Fix this branch: target is current ORG_pc
	  fix(L, ORG_pc);

	  // Move to next branch in chain
	  L = L1;
    }
}

static void FixLinkWith(LONGINT L0, LONGINT dst) {
    // For 65C816: fix a chain of forward branches to a specific destination
    // L0 is the address of the offset byte of the most recent branch
    // dst is the target address
    LONGINT L1;
	LONGINT code_index;
    while (L0 != 0) {
	  	code_index = L0 - CODE_ORG;  // Index for low byte of offset

        // Read the 2-byte chain link BEFORE fixing (fix() will overwrite it)
        L1 = code[code_index] | (code[code_index + 1] << 8);
        
        // Fix this branch to the specified destination
        fix(L0, dst);
        
        // Move to next branch in chain
        L0 = L1;
    }
}

static LONGINT merged(LONGINT L0, LONGINT L1) {
    LONGINT L2, L3;
	LONGINT code_index;
    if (L0 != 0) {
        L3 = L0;
        do {
            L2 = L3;
			code_index = L2 - CODE_ORG;  // Index for low byte of offset

            // For BRL instructions, read 2-byte chain link in little-endian format
            L3 = code[code_index] | (code[code_index + 1] << 8);
        } while (L3 != 0);
        
        // Update the 2-byte offset field with L1 in little-endian format
        code[code_index] = L1 & 0xFF;
        code[code_index + 1] = (L1 >> 8) & 0xFF;
        L1 = L0;
    }
    return L1;
}

// NilCheck is now inlined in ORG_DeRef for 4-byte pointer support

// Returns the number of registers used
static int load(ORG_Item *x) {
    if (x->mode != Reg) {
        if (x->mode == ORB_Const) {
            if (x->type->form == ORB_NilTyp || x->type->form == ORB_Pointer) {
                // NIL or pointer constant: load 4 bytes (2 words, both zero for NIL)
                Set16(1, 1);
                codegen_gen(sSTZ, DirectPage, reg_addr(RH), 0);      // STZ addr (0)
                codegen_gen(sSTZ, DirectPage, reg_addr(RH + 1), 0);  // STZ bank (0)
                x->r = RH;
                incR(); incR();
            } else if (x->type->form == ORB_Proc) {
                if (x->r > 0 || (x->r == 0 && x->b == 0)) {
                    // Local (nested) or non-exported procedure: cannot be used as proc var
                    ORS_Mark("not exportd");
                } else if (x->r == 0 && x->b == 1) {
                    // Same-module exported procedure address
                    // PER pushes PC + operand + 3; we want it to push proc address
                    // operand = proc_addr - PER_addr - 3 = x->a - ORG_pc - 3
                    Set16(1, 1);
                    int per_addr = ORG_pc;
                    int per_operand = x->a - per_addr - 3;
                    codegen_gen(sPER, Immediate, per_operand & 0xFFFF, 0);
                    codegen_gen(sPLA, Implied, 0, 0);
                    codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);
                    // Store program bank byte into R[RH+1]
                    codegen_gen(sSTZ, DirectPage, reg_addr(RH + 1), 0);
                    codegen_gen(sPHK, Implied, 0, 0);
                    Set8(1, 0);
                    codegen_gen(sPLA, Implied, 0, 0);
                    codegen_gen(sSTA, DirectPage, reg_addr(RH + 1), 0);
                    Set16(1, 0);
                    x->r = RH;
                    incR(); incR();
                } else {
                    // Imported procedure address
                    // Encode (mno << 8) | exno in PER operand, add to relocation chain
                    Set16(1, 1);
                    int mno = -(x->r);
                    int exno = x->a;
                    int encoded = (mno << 8) | (exno & 0xFF);
                    reloc[relocC++] = ORG_pc;
                    codegen_gen(sPER, Immediate, encoded, 0);
                    codegen_gen(sPLA, Implied, 0, 0);
                    codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);
                    // For imported procs, bank is set by emulator relocation
                    codegen_gen(sSTZ, DirectPage, reg_addr(RH + 1), 0);
                    codegen_gen(sPHK, Implied, 0, 0);
                    Set8(1, 0);
                    codegen_gen(sPLA, Implied, 0, 0);
                    codegen_gen(sSTA, DirectPage, reg_addr(RH + 1), 0);
                    Set16(1, 0);
                    x->r = RH;
                    incR(); incR();
                }
            } else if (x->type->form == ORB_Real) {
                // REAL constant: split 32-bit IEEE value into two 16-bit halves
                Set16(1, 1);
                codegen_gen(sLDA, Immediate, x->a & 0xFFFF, 0);
                codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);
                codegen_gen(sLDA, Immediate, (x->a >> 16) & 0xFFFF, 0);
                codegen_gen(sSTA, DirectPage, reg_addr(RH + 1), 0);
                x->r = RH;
                incR(); incR();
            } else if ((x->a <= 0xFFFF) && (x->a >= -0x10000)) {
              if (x->type->size == 1) {
                Set8(1, 0);
                codegen_gen(sLDA, Immediate, x->a & 0xFF, 0);  // LDA #constant (8-bit)
                Set16(1, 0);
                codegen_gen(sAND, Immediate, 0x00FF, 0);        // AND #$00FF zero-extend
                codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);  // STA $reg (16-bit)
              } else {
                Set16(1, 1);
                codegen_gen(sLDA, Immediate, x->a & 0xFFFF, 0);  // LDA #constant
                codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);  // STA $reg
              }
              x->r = RH;
              incR();
            } else {
    // RISC: Put1(Mov + U, RH, 0, (x->a / 0x10000) % 0x10000);
                if (x->a % 0x10000 != 0) {
    // RISC: Put1(Ior, RH, RH, x->a % 0x10000);
                }
                x->r = RH;
                incR();
            }
        } else if (x->mode == ORB_Var) {
            if (x->r > 0) {
                // 65C816: Load stack-based local variable
              if (x->type->form == ORB_Pointer || x->type->form == ORB_NilTyp || x->type->form == ORB_Real || x->type->form == ORB_Proc) {
                // 4-byte load: (addr+bank for pointer/proc, low+high for REAL) into 2 registers
                Set16(1, 1);
                codegen_gen(sLDA, StackRelative, x->a + frame, 0);          // LDA offset,S (low word)
                codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);           // STA $reg
                codegen_gen(sLDA, StackRelative, x->a + 2 + frame, 0);    // LDA offset+2,S (high word)
                codegen_gen(sSTA, DirectPage, reg_addr(RH + 1), 0);       // STA $reg+1
                x->r = RH;
                incR(); incR();
              } else if (x->type->size == 1) {
                // Byte load from stack (handles BYTE, BOOL, CHAR)
                Set8(1, 0);
                codegen_gen(sLDA, StackRelative, x->a + frame, 0);          // LDA x->a,S (8-bit)
                Set16(1, 0);
                codegen_gen(sAND, Immediate, 0x00FF, 0);                  // AND #$00FF zero-extend
                codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);           // STA $reg (16-bit)
                x->r = RH;
                incR();
              } else {
                // Word load from stack (handles INTEGER and other multi-byte types)
                Set16(1, 1);
                codegen_gen(sLDA, StackRelative, x->a + frame, 0);          // LDA x->a,S (16-bit)
                codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);           // STA $reg
                x->r = RH;
                incR();
              }
            } else {
              // 65C816: Load module global variable
              int sb = GetSB(x->r);
              if (x->type->form == ORB_Pointer || x->type->form == ORB_NilTyp || x->type->form == ORB_Real || x->type->form == ORB_Proc) {
                // 4-byte load: (addr+bank for pointer/proc, low+high for REAL) into 2 registers
                Set16(1, 1);
                codegen_gen(sLDY, Immediate, x->a, 0);
                codegen_gen(sLDA, DirectPageIndirectIndexedY, sb, 0);     // low word
                codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);
                codegen_gen(sLDY, Immediate, x->a + 2, 0);
                codegen_gen(sLDA, DirectPageIndirectIndexedY, sb, 0);     // high word
                codegen_gen(sSTA, DirectPage, reg_addr(RH + 1), 0);
                x->r = RH;
                incR(); incR();
              } else if (x->type->size == 1) {
                // Byte load from global (handles BYTE, BOOL, CHAR)
                Set8(1, 0);
                codegen_gen(sLDY, Immediate, x->a, 0);
                codegen_gen(sLDA, DirectPageIndirectIndexedY, sb, 0);
                Set16(1, 0);
                codegen_gen(sAND, Immediate, 0x00FF, 0);                  // AND #$00FF zero-extend
                codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);           // STA $reg (16-bit)
                x->r = RH;
                incR();
              } else {
                // Word load from global (handles INTEGER and other multi-byte types)
                Set16(1, 1);
                codegen_gen(sLDY, Immediate, x->a, 0);
                codegen_gen(sLDA, DirectPageIndirectIndexedY, sb, 0);
                codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);
                x->r = RH;
                incR();
              }
            }
        } else if (x->mode == ORB_Par) {
		  // 65C816: Load VAR parameter - first load the 4-byte pointer into registers,
		  // then dereference through the pointer to get the actual value
		  
		  // Load the 4-byte pointer from stack into two registers
		  Set16(1, 1);
		  // Load 16-bit address into first register
		  codegen_gen(sLDA, StackRelative, x->a + frame, 0);  // LDA param_offset,S (load address)
		  codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);   // STA $reg0 (store address)

		  // Load data bank into second register
		  codegen_gen(sLDA, StackRelative, x->a + 2 + frame, 0); // LDA param_offset+2,S (load data bank)
		  codegen_gen(sSTA, DirectPage, reg_addr(RH + 1), 0); // STA $reg1 (store data bank)
		  
		  // Now dereference through the pointer using DirectPageIndirectLong
		  // Apply field offset x->b if nonzero (e.g., record field through VAR param)
		  if (x->type->form == ORB_Real || x->type->form == ORB_Pointer || x->type->form == ORB_Proc) {
			// 4-byte load through pointer (REAL: low+high, Pointer/Proc: addr+bank)
			Set16(1, 1);
			if (x->b != 0) {
			  codegen_gen(sLDY, Immediate, x->b + 2, 0);
			  codegen_gen(sLDA, DirectPageIndirectLongIndexedY, reg_addr(RH), 0);
			  codegen_gen(sPHA, Implied, 0, 0);  // save high word
			  codegen_gen(sLDY, Immediate, x->b, 0);
			  codegen_gen(sLDA, DirectPageIndirectLongIndexedY, reg_addr(RH), 0);
			} else {
			  codegen_gen(sLDY, Immediate, 2, 0);
			  codegen_gen(sLDA, DirectPageIndirectLongIndexedY, reg_addr(RH), 0);
			  codegen_gen(sPHA, Implied, 0, 0);  // save high word
			  codegen_gen(sLDA, DirectPageIndirectLong, reg_addr(RH), 0);
			}
			codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);         // low word
			codegen_gen(sPLA, Implied, 0, 0);                        // restore high word
			codegen_gen(sSTA, DirectPage, reg_addr(RH + 1), 0);     // high word
			x->r = RH;
			incR(); incR();
		  } else if (x->type->size == 1) {
			// Byte load through pointer
			Set8(1, 0);  // 8-bit accumulator
			if (x->b != 0) {
			  codegen_gen(sLDY, Immediate, x->b, 0);
			  codegen_gen(sLDA, DirectPageIndirectLongIndexedY, reg_addr(RH), 0);
			} else {
			  codegen_gen(sLDA, DirectPageIndirectLong, reg_addr(RH), 0);
			}
			Set16(1, 0);  // back to 16-bit accumulator
			codegen_gen(sAND, Immediate, 0x00FF, 0);                // AND #$00FF zero-extend
			codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);         // STA $reg (16-bit)
			x->r = RH;
			incR();
		  } else {
			// Word load through pointer
			Set16(1, 1); // 16-bit accumulator
			if (x->b != 0) {
			  codegen_gen(sLDY, Immediate, x->b, 0);
			  codegen_gen(sLDA, DirectPageIndirectLongIndexedY, reg_addr(RH), 0);
			} else {
			  codegen_gen(sLDA, DirectPageIndirectLong, reg_addr(RH), 0);
			}
			codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);         // STA $reg2 (store result)
			x->r = RH;
			incR();
		  }
        } else if (x->mode == RegI) {
          // 65C816: Load value from long indirect address in register + offset
          // RegI items occupy 2 registers: addr in x->r, bank in x->r+1
          if (x->type->form == ORB_Pointer || x->type->form == ORB_NilTyp || x->type->form == ORB_Real || x->type->form == ORB_Proc) {
            // Loading 4 bytes through RegI (pointer/proc: addr+bank, REAL: low+high)
            Set16(1, 1);
            // Load bank word first (base pointer still intact)
            codegen_gen(sLDY, Immediate, x->a + 2, 0);
            codegen_gen(sLDA, DirectPageIndirectLongIndexedY, reg_addr(x->r), 0);
            codegen_gen(sPHA, Implied, 0, 0);                            // save bank on stack
            // Load addr word
            if (x->a == 0) {
              codegen_gen(sLDA, DirectPageIndirectLong, reg_addr(x->r), 0);
            } else {
              codegen_gen(sLDY, Immediate, x->a, 0);
              codegen_gen(sLDA, DirectPageIndirectLongIndexedY, reg_addr(x->r), 0);
            }
            codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);           // store addr
            codegen_gen(sPLA, Implied, 0, 0);                            // restore bank
            codegen_gen(sSTA, DirectPage, reg_addr(x->r + 1), 0);       // store bank
            // Keep 2 registers (no RH change)
          } else if (x->type->size == 1) {
            Set8(1, 0);
            if (x->a == 0) {
              codegen_gen(sLDA, DirectPageIndirectLong, reg_addr(x->r), 0);
            } else {
              codegen_gen(sLDY, Immediate, x->a, 0);
              codegen_gen(sLDA, DirectPageIndirectLongIndexedY, reg_addr(x->r), 0);
            }
            Set16(1, 0);
            codegen_gen(sAND, Immediate, 0x00FF, 0);
            codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);
            RH--;  // free bank register (x->r+1)
          } else {
            Set16(1, 1);
            if (x->a == 0) {
              codegen_gen(sLDA, DirectPageIndirectLong, reg_addr(x->r), 0);
            } else {
              codegen_gen(sLDY, Immediate, x->a, 0);
              codegen_gen(sLDA, DirectPageIndirectLongIndexedY, reg_addr(x->r), 0);
            }
            codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);
            RH--;  // free bank register (x->r+1)
          }
        } else if (x->mode == Cond) {
          // Materialize boolean condition into a 0/1 value in a register.
          // Pattern:
          //   emitBranch(negated(cond)) -> FALSE_PATH  (if condition false, jump ahead)
          //   [fix TRUE chain here]
          //   LDA #1                                   (TRUE value)
          //   BRA END                                  (skip FALSE path)
          //   FALSE_PATH:
          //   [fix FALSE chain here]
          //   LDA #0                                   (FALSE value)
          //   END:
          //   STA $reg                                 (store result)

          // Branch to FALSE path when condition is NOT met
          emitBranch(negated(x->r), x->orig_type, Fixup, x->a);
          LONGINT false_chain = ORG_pc - 2;  // BRL offset field = new FALSE chain head

          // TRUE path
          ORG_FixLink(x->b);
          codegen_gen(sLDA, Immediate, 1, 0);           // LDA #1
          codegen_gen(sBRA, ProgramCounterRelative, ORG_pc + 2 + 3, 0);  // BRA past LDA #0

          // FALSE path
          ORG_FixLink(false_chain);
          codegen_gen(sLDA, Immediate, 0, 0);           // LDA #0

          // Store result
          codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);
          x->r = RH;
          incR();
        }
        x->mode = Reg;
    }
	return 1; // Temporary, later on we will update this
}

static void loadAdr(ORG_Item *x) {
    if (x->mode == ORB_Var) {
        if (x->r > 0) {
            // 65C816: Local variable address = SP + (x->a + frame)
            Set16(1, 1);
            codegen_gen(sTSC, Implied, 0, 0);                             // TSC (SP -> A)
            codegen_gen(sCLC, Implied, 0, 0);                             // CLC
            codegen_gen(sADC, Immediate, x->a + frame, 0);                // ADC #offset
            codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);               // STA $reg
            codegen_gen(sSTZ, DirectPage, reg_addr(RH + 1), 0);           // STZ $reg+1 (bank=0)
        } else {
            // 65C816: Global variable - calculate absolute address
            int sb = GetSB(x->r);
            Set16(1, 1);
            codegen_gen(sLDA, Immediate, x->a, 0);                              // LDA #offset
            codegen_gen(sCLC, Implied, 0, 0);                                   // CLC
            codegen_gen(sADC, DirectPage, sb, 0);                               // ADC SB/SB_TEMP
            codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);                     // STA $reg
            // Bank: use BANK_DP for own module, SB_TEMP_BANK for imports
            if (x->r >= 0) {
              codegen_gen(sLDA, DirectPage, BANK_DP, 0);                        // own module bank
            } else {
              codegen_gen(sLDA, DirectPage, SB_TEMP_BANK, 0);                   // import bank
            }
            codegen_gen(sSTA, DirectPage, reg_addr(RH + 1), 0);                 // STA $reg
        }
        x->r = RH;
        incR();
        incR();
    } else if (x->mode == ORB_Par) {
        // 65C816: Load address from VAR parameter (global variables only for now)
        // The stack contains the absolute address of the variable
        Set16(1, 1);
        codegen_gen(sLDA, StackRelative, x->a + frame, 0);         // LDA param_offset,S (load address)
        codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);          // STA $reg
        codegen_gen(sLDA, StackRelative, x->a + 2 + frame, 0);   // LDA param_offset+2,S (load address)
        codegen_gen(sSTA, DirectPage, reg_addr(RH + 1), 0);      // STA $reg
        if (x->b != 0) {
            // Add offset if present
            codegen_gen(sLDA, DirectPage, reg_addr(RH), 0);      // LDA $reg
            codegen_gen(sCLC, Implied, 0, 0);                    // CLC
            codegen_gen(sADC, Immediate, x->b, 0);               // ADC #offset  
            codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);      // STA $reg
        }
        x->r = RH;
        incR();
        incR();
    } else if (x->mode == RegI) {
        // 65C816: Add offset to register address
        if (x->a != 0) {
            Set16(1, 1);
            codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);       // LDA address
            codegen_gen(sCLC, Implied, 0, 0);                       // CLC
            codegen_gen(sADC, Immediate, x->a, 0);                  // ADC #offset
            codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);       // STA address
        }
    } else {
        ORS_Mark("address error");
    }
    x->mode = Reg;
}

static void loadCond(ORG_Item *x) {
  if (x->type->form == ORB_Bool) {
	if (x->mode == ORB_Const) {
	  // For boolean constants: FALSE(0) -> 15, TRUE(1) -> 7
	  // This maps to branch conditions: 15=never, 7=always
	  x->r = 15 - x->a * 8;
	} else {
	  load(x);
	  // 65C816: Explicitly load the register to set Z flag.
	  // load() may be a no-op when item is already in Reg mode (e.g. function return),
	  // and even when load() generates LDA+STA, the STA doesn't affect flags.
	  // So always emit LDA R[x->r] to ensure Z flag reflects the actual value.
	  Set16(1, 1);
	  codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);
	  x->r = NE;  // NE (9) = branch if not zero (TRUE condition)
	  RH--;
	}
	x->mode = Cond;
	x->orig_type = x->type;  // Preserve type for emitBranch (boolean, not signed int)
	x->a = 0;  // FALSE branch chain (initially empty)
	x->b = 0;  // TRUE branch chain (initially empty)
  } else {
	ORS_Mark("not Boolean?");
  }
}

static void loadTypTagAdr(ORB_Type *T) {
    ORG_Item x;
    x.mode = ORB_Var;
    x.a = T->len;
    x.r = -T->mno;
    loadAdr(&x);
}

static void loadStringAdr(ORG_Item *x) {
    // 65C816: Compute string address = SB + ORG_varsize + x->a
    // We need the ADDRESS itself (for use as a pointer), not the data at that address.
    Set16(1, 1);
    codegen_gen(sLDA, DirectPage, SB_DP, 0);           // Load SB value
    codegen_gen(sCLC, Implied, 0, 0);                          // CLC
    codegen_gen(sADC, Immediate, ORG_varsize + x->a, 0);      // Add string offset
    codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);            // Store address
    x->mode = Reg;
    x->r = RH;
    incR();
}

// Item creation functions
void ORG_MakeConstItem(ORG_Item *x, ORB_Type *typ, LONGINT val) {
    x->mode = ORB_Const;
    x->type = typ;
    x->a = val;
}

void ORG_MakeRealItem(ORG_Item *x, REAL val) {
    x->mode = ORB_Const;
    x->type = realType;
    x->a = 0;
    memcpy(&x->a, &val, sizeof(REAL));
}

void ORG_MakeStringItem(ORG_Item *x, LONGINT len) {
    LONGINT i = 0;
    x->mode = ORB_Const;
    x->type = strType;
    x->a = strx;
    x->b = len;
    
    if (strx + len < maxStrx) {
        while (len > 0) {
            str[strx] = ORS_str[i];
            strx++;
            i++;
            len--;
        }
        // Remove 4-byte alignment padding for strings
    } else {
        ORS_Mark("too many strings");
    }
}

void ORG_MakeDataItem(ORG_Item *x, ORB_Type *typ, LONGINT offset, LONGINT size) {
    x->mode = ORB_Const;
    x->type = typ;
    x->a = offset;  // offset into str[]
    x->b = size;    // total byte count
}

LONGINT ORG_StrOffset(void) {
    return strx;
}

void ORG_PutByte(int b) {
    if (strx < maxStrx) {
        str[strx++] = b & 0xFF;
    } else {
        ORS_Mark("string space overflow");
    }
}

void ORG_MakeItem(ORG_Item *x, ORB_Object *y, LONGINT curlev) {
    x->mode = y->class;
    x->type = y->type;
    x->a = y->val;
    x->rdo = y->rdo;
    
    
    if (y->class == ORB_Par) {
        x->b = 0;
    } else if ((y->class == ORB_Const) && (y->type->form == ORB_String)) {
        x->b = y->lev;
    } else if ((y->class == ORB_Const) &&
               (y->type->form == ORB_Array || y->type->form == ORB_Record)) {
        if (y->lev < 0) {
            // Imported structured constant: treat as imported read-only variable
            x->mode = ORB_Var;
            x->r = y->lev;  // -mno
            x->rdo = 1;
        }
        x->b = y->type->size;  // byte size from type
    } else if ((y->class == ORB_Const) && (y->type->form == ORB_Proc)) {
        x->r = y->lev;
        x->b = y->expo ? 1 : 0;  // Store export flag for procedure calls
    } else {
        x->r = y->lev;
    }
    
    if ((y->lev > 0) && (y->lev != curlev) && (y->class != ORB_Const)) {
        ORS_Mark("not accessible ");
    }
}

// Selector operations
void ORG_Field(ORG_Item *x, ORB_Object *y) {
    if (x->mode == ORB_Var) {
        if (x->r >= 0) {
            x->a = x->a + y->val;
        } else {
            loadAdr(x);
            x->mode = RegI;
            x->a = y->val;
        }
    } else if (x->mode == RegI) {
        x->a = x->a + y->val;
    } else if (x->mode == ORB_Par) {
        x->b = x->b + y->val;
    } else if (x->mode == ORB_Const) {
        // Structured constant: adjust str offset, convert to global Var
        x->a = ORG_varsize + x->a + y->val;
        x->mode = ORB_Var;
        x->r = 0;  // module level
    }
}

void ORG_Index(ORG_Item *x, ORG_Item *y) {
    LONGINT s, lim;
    // BOOLEAN original_rdo = x->rdo;  // Preserve the read-only flag
    s = x->type->base->size;
    lim = x->type->len;
    
    if ((y->mode == ORB_Const) && (lim >= 0)) {
        // Fixed array with constant index - do compile-time bounds check
        if ((y->a < 0) || (y->a >= lim)) {
            ORS_Mark("bad index");
        }
        // 65C816: Check if computed offset would exceed 8-bit StackRelative limit
        if ((x->mode == ORB_Var) && (x->r > 0) && (y->a * s + x->a + frame > 255)) {
            // Offset too large for LDA nn,S — use computed address (TSC+ADC) path
            // Convert constant index to register and fall through to runtime path
            load(y);
            goto runtime_index;
        }
        if ((x->mode == ORB_Var) || (x->mode == RegI)) {
            x->a = y->a * s + x->a;
        } else if (x->mode == ORB_Par) {
            x->b = y->a * s + x->b;
        } else if (x->mode == ORB_Const) {
            // Structured constant: adjust str offset, convert to global Var
            // Data lives at SB + varsize + x->a in the string section
            x->a = ORG_varsize + y->a * s + x->a;
            x->mode = ORB_Var;
            x->r = 0;  // module level
        }
    } else {
        runtime_index:
        // Runtime indexing (non-constant index OR open array)
        load(y);
        if (check) {
            if (lim >= 0) {
                // 65C816: Compare index with array limit for fixed arrays
                Set16(1, 1);
                codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);    // LDA index
                codegen_gen(sCMP, Immediate, lim, 0);                // CMP #limit
				Trap(LT, 1);  // Branch if index >= length
            } else {
                if ((x->mode == ORB_Var) || (x->mode == ORB_Par)) {
                    // 65C816: Load array length from stack for open arrays and compare with index
					// We want to trap if index >= array_length  
					// Compare: index - array_length, trap if NOT(index < array_length)
                    Set16(1, 1);
                    codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);       // LDA index
					codegen_gen(sCMP, StackRelative, x->a + 4 + frame, 0);  // CMP length,S: index - array_length
                    Trap(LT, 1);  // Trap if NOT(index < array_length), i.e., if index >= array_length
                } else {
                    ORS_Mark("error in Index");
                }
            }
        }
        
        // 65C816: Multiply index by element size
        Set16(1, 1);
        if (s > 1) {
          // Count trailing zeros to find power-of-2 component
          int shifts = 0;
          LONGINT ts = s;
          while (ts > 1 && !(ts & 1)) { ts >>= 1; shifts++; }
          if (ts == 1) {
            // Pure power of 2: just shift
            for (int i = 0; i < shifts; i++) {
              codegen_gen(sASL, DirectPage, reg_addr(y->r), 0);
            }
          } else {
            // General multiply by compile-time constant using shift-and-add
            int idx_reg = reg_addr(y->r);
            // Apply trailing zero shifts first
            for (int i = 0; i < shifts; i++) {
              codegen_gen(sASL, DirectPage, idx_reg, 0);
            }
            // ts is odd > 1: multiply by ts using A as accumulator
            codegen_gen(sLDA, DirectPage, idx_reg, 0);  // A = index * 2^shifts (bit 0 of ts)
            LONGINT remaining = ts >> 1;
            while (remaining > 0) {
              codegen_gen(sASL, DirectPage, idx_reg, 0);  // shift base value
              if (remaining & 1) {
                codegen_gen(sCLC, Implied, 0, 0);
                codegen_gen(sADC, DirectPage, idx_reg, 0);  // add to accumulator
              }
              remaining >>= 1;
            }
            codegen_gen(sSTA, DirectPage, idx_reg, 0);  // store result
          }
        }
        
        if (x->mode == ORB_Var) {
            if (x->r > 0) {
                // 65C816: Local array - compute element address from stack pointer
                Set16(1, 1);
                codegen_gen(sTSC, Implied, 0, 0);                         // TSC (A = SP)
                codegen_gen(sCLC, Implied, 0, 0);                         // CLC
                codegen_gen(sADC, Immediate, x->a + frame, 0);            // ADC #stack_offset
                codegen_gen(sADC, DirectPage, reg_addr(y->r), 0);         // ADC scaled_index
                codegen_gen(sSTA, DirectPage, reg_addr(y->r), 0);         // STA element_addr
            } else {
                // 65C816: Global array - compute element address from SB
                int sb = GetSB(x->r);
                Set16(1, 1);
                codegen_gen(sLDA, DirectPage, sb, 0);                     // LDA SB
                codegen_gen(sCLC, Implied, 0, 0);                         // CLC
                codegen_gen(sADC, Immediate, x->a, 0);                    // ADC #array_base_offset
                codegen_gen(sADC, DirectPage, reg_addr(y->r), 0);         // ADC scaled_index
                codegen_gen(sSTA, DirectPage, reg_addr(y->r), 0);         // STA element_addr
            }
            // Allocate and zero bank register for long indirect consistency
            codegen_gen(sSTZ, DirectPage, reg_addr(RH), 0);               // zero bank register
            x->a = 0;
            x->r = y->r;
            x->mode = RegI;
            incR();  // reserve bank register
        } else if (x->mode == ORB_Par) {
            // 65C816: Open array parameter - compute element address
            // Load array base address and bank from stack
            Set16(1, 1);
            codegen_gen(sLDA, StackRelative, x->a + frame, 0);      // LDA base_addr,S
            codegen_gen(sCLC, Implied, 0, 0);                       // CLC
            codegen_gen(sADC, DirectPage, reg_addr(y->r), 0);       // ADC scaled_index
            codegen_gen(sSTA, DirectPage, reg_addr(y->r), 0);       // STA element_addr
            // Load bank into next register
            codegen_gen(sLDA, StackRelative, x->a + 2 + frame, 0);  // LDA bank,S
            codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);         // STA bank_reg
            incR();  // reserve bank register

            x->mode = RegI;    // Register indirect mode for both read/write
            x->r = y->r;       // Register containing element address
            x->a = x->b;       // Preserve original offset
        } else if (x->mode == ORB_Const) {
            // Structured constant: compute address = SB + varsize + str_offset + scaled_index
            Set16(1, 1);
            codegen_gen(sLDA, DirectPage, SB_DP, 0);                    // LDA SB
            codegen_gen(sCLC, Implied, 0, 0);                           // CLC
            codegen_gen(sADC, Immediate, ORG_varsize + x->a, 0);        // ADC #(varsize+str_offset)
            codegen_gen(sADC, DirectPage, reg_addr(y->r), 0);           // ADC scaled_index
            codegen_gen(sSTA, DirectPage, reg_addr(y->r), 0);           // STA element_addr
            codegen_gen(sSTZ, DirectPage, reg_addr(RH), 0);             // zero bank register
            x->a = 0;
            x->r = y->r;
            x->mode = RegI;
            incR();  // reserve bank register
        } else if (x->mode == RegI) {
            // 65C816: Add index offset to existing address
            Set16(1, 1);
            codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);       // LDA current_addr
            codegen_gen(sCLC, Implied, 0, 0);                       // CLC
            codegen_gen(sADC, DirectPage, reg_addr(y->r), 0);       // ADC index_offset
            codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);       // STA result
            RH--;  // Deallocate y->r register
        }
    }

    // Restore the read-only flag - indexed elements inherit the read-only status of the array
    //x->rdo = original_rdo;
}

void ORG_DeRef(ORG_Item *x) {
    // 65C816: Dereference a pointer — load 4-byte pointer value into 2 registers
    // Result: addr in reg(x->r), bank in reg(x->r+1), mode=RegI, a=0, b=0
    Set16(1, 1);

    if (x->mode == ORB_Var) {
        if (x->r > 0) {
            // Local pointer variable: load 4 bytes from stack
            codegen_gen(sLDA, StackRelative, x->a + frame, 0);        // addr word
            codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);
            codegen_gen(sLDA, StackRelative, x->a + 2 + frame, 0);    // bank word
            codegen_gen(sSTA, DirectPage, reg_addr(RH + 1), 0);
        } else {
            // Global pointer variable: load 4 bytes through SB
            int sb = GetSB(x->r);
            codegen_gen(sLDY, Immediate, x->a, 0);
            codegen_gen(sLDA, DirectPageIndirectIndexedY, sb, 0);      // addr word
            codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);
            codegen_gen(sLDY, Immediate, x->a + 2, 0);
            codegen_gen(sLDA, DirectPageIndirectIndexedY, sb, 0);      // bank word
            codegen_gen(sSTA, DirectPage, reg_addr(RH + 1), 0);
        }
        // Inline NilCheck: ORA both words, trap if zero
        if (check) {
            codegen_gen(sLDA, DirectPage, reg_addr(RH), 0);
            codegen_gen(sORA, DirectPage, reg_addr(RH + 1), 0);
            Trap(NE, 4);
        }
        x->r = RH;
        incR(); incR();
    } else if (x->mode == ORB_Par) {
        // VAR param pointer: load the 4-byte address from stack, then load 4-byte pointer through it
        codegen_gen(sLDA, StackRelative, x->a + frame, 0);              // load VAR param addr
        codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);
        codegen_gen(sLDA, StackRelative, x->a + 2 + frame, 0);        // load VAR param bank
        codegen_gen(sSTA, DirectPage, reg_addr(RH + 1), 0);
        // Load 4-byte pointer through long indirect
        codegen_gen(sLDY, Immediate, x->b + 2, 0);
        codegen_gen(sLDA, DirectPageIndirectLongIndexedY, reg_addr(RH), 0);  // bank word of pointer
        codegen_gen(sPHA, Implied, 0, 0);                              // save on stack
        if (x->b == 0) {
            codegen_gen(sLDA, DirectPageIndirectLong, reg_addr(RH), 0);      // addr word
        } else {
            codegen_gen(sLDY, Immediate, x->b, 0);
            codegen_gen(sLDA, DirectPageIndirectLongIndexedY, reg_addr(RH), 0);
        }
        codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);               // store addr
        codegen_gen(sPLA, Implied, 0, 0);
        codegen_gen(sSTA, DirectPage, reg_addr(RH + 1), 0);           // store bank
        // Inline NilCheck
        if (check) {
            codegen_gen(sLDA, DirectPage, reg_addr(RH), 0);
            codegen_gen(sORA, DirectPage, reg_addr(RH + 1), 0);
            Trap(NE, 4);
        }
        x->r = RH;
        incR(); incR();
    } else if (x->mode == RegI) {
        // Chained deref (e.g., p^.next^): load 4-byte pointer through current long indirect
        // Load bank word first (base pointer still intact)
        codegen_gen(sLDY, Immediate, x->a + 2, 0);
        codegen_gen(sLDA, DirectPageIndirectLongIndexedY, reg_addr(x->r), 0);
        codegen_gen(sPHA, Implied, 0, 0);                              // save bank
        if (x->a == 0) {
            codegen_gen(sLDA, DirectPageIndirectLong, reg_addr(x->r), 0);
        } else {
            codegen_gen(sLDY, Immediate, x->a, 0);
            codegen_gen(sLDA, DirectPageIndirectLongIndexedY, reg_addr(x->r), 0);
        }
        codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);             // overwrite addr
        codegen_gen(sPLA, Implied, 0, 0);
        codegen_gen(sSTA, DirectPage, reg_addr(x->r + 1), 0);         // overwrite bank
        // Inline NilCheck
        if (check) {
            codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);
            codegen_gen(sORA, DirectPage, reg_addr(x->r + 1), 0);
            Trap(NE, 4);
        }
        // Reuses same 2 registers, no RH change
    } else if (x->mode != Reg) {
        ORS_Mark("bad mode in DeRef");
    }
    x->mode = RegI;
    x->a = 0;
    x->b = 0;
}

static void Q(ORB_Type *T, LONGINT *dcw) {
    if (T->base != NULL) {
        Q(T->base, dcw);
        data[*dcw] = T->len;      // addr_lo (module-relative TD offset)
        data[*dcw + 1] = 0;       // addr_hi (bank, 0 for now)
        td_fixup[td_fixupC][0] = *dcw * 2;  // byte offset of lo word
        td_fixup[td_fixupC][1] = T->mno;    // 0=own module, >0=import
        td_fixupC++;
        *dcw += 2;                 // 2 words per ancestor
    }
}

static void FindPtrFlds(ORB_Type *typ, LONGINT off, LONGINT *dcw) {
    ORB_Object *fld;
    LONGINT i, s;
    
    if ((typ->form == ORB_Pointer) || (typ->form == ORB_NilTyp)) {
        data[*dcw] = off;
        (*dcw)++;
    } else if (typ->form == ORB_Record) {
        fld = typ->dsc;
        while (fld != NULL) {
            FindPtrFlds(fld->type, fld->val + off, dcw);
            fld = fld->next;
        }
    } else if (typ->form == ORB_Array) {
        s = typ->base->size;
        for (i = 0; i < typ->len; i++) {
            FindPtrFlds(typ->base, i * s + off, dcw);
        }
    }
}

void ORG_BuildTD(ORB_Type *T, LONGINT *dc) {
    LONGINT dcw, k;
    dcw = *dc / 2;  // 2-byte entries

    T->len = *dc;   // byte offset of this TD in module data area
    data[dcw] = T->size;  // actual allocation size (no RISC rounding)
    dcw++;
    k = T->nofpar;  // extension level

    if (k > 3) {
        ORS_Mark("ext level too large");
    } else {
        Q(T, &dcw);
        while (k < 3) {
            data[dcw] = 0xFFFF;
            data[dcw + 1] = 0xFFFF;
            dcw += 2;
            k++;
        }
    }

    FindPtrFlds(T, 0, &dcw);
    data[dcw] = 0xFFFF;
    dcw++;
    tdx = dcw;
    *dc = dcw * 2;  // 2 bytes per entry

    if (tdx >= maxTD) {
        ORS_Mark("too many record types");
        tdx = 0;
    }
}

void ORG_TypeTest(ORG_Item *x, ORB_Type *T, BOOLEAN varpar, BOOLEAN isguard) {
    if (T == NULL) {
        if (x->mode >= Reg) {
            RH--;
        }
        SetCC(x, AL);  // always true
    } else if (varpar) {
        // VAR record param type test: load 4-byte tag from stack frame
        // Stack layout: [addr:2][bank:2][tag_lo:2][tag_hi:2]
        Set16(1, 1);

        // Load 4-byte tag into temp register pair
        incR(); incR();
        codegen_gen(sLDA, StackRelative, x->a + 4 + frame, 0);  // tag_lo
        codegen_gen(sSTA, DirectPage, reg_addr(RH - 2), 0);
        codegen_gen(sLDA, StackRelative, x->a + 6 + frame, 0);  // tag_hi
        codegen_gen(sSTA, DirectPage, reg_addr(RH - 1), 0);

        // Add ancestor offset: 2 + (nofpar-1)*4
        // TD layout: size(2), ancestor[0](4), ancestor[1](4), ancestor[2](4)
        LONGINT offset = 2 + (T->nofpar - 1) * 4;
        codegen_gen(sCLC, Implied, 0, 0);
        codegen_gen(sLDA, DirectPage, reg_addr(RH - 2), 0);
        codegen_gen(sADC, Immediate, offset, 0);
        codegen_gen(sSTA, DirectPage, reg_addr(RH - 2), 0);
        codegen_gen(sLDA, DirectPage, reg_addr(RH - 1), 0);
        codegen_gen(sADC, Immediate, 0, 0);  // carry propagation
        codegen_gen(sSTA, DirectPage, reg_addr(RH - 1), 0);

        // Load 4-byte ancestor via indirect long
        codegen_gen(sLDA, DirectPageIndirectLong, reg_addr(RH - 2), 0);  // ancestor_lo
        codegen_gen(sPHA, Implied, 0, 0);
        codegen_gen(sLDY, Immediate, 2, 0);
        codegen_gen(sLDA, DirectPageIndirectLongIndexedY, reg_addr(RH - 2), 0);  // ancestor_hi
        codegen_gen(sSTA, DirectPage, reg_addr(RH - 1), 0);
        codegen_gen(sPLA, Implied, 0, 0);
        codegen_gen(sSTA, DirectPage, reg_addr(RH - 2), 0);

        // XOR+ORA compare: target = SB + T->len (4-byte)
        int sb = GetSB(-T->mno);
        codegen_gen(sLDA, DirectPage, sb, 0);
        codegen_gen(sCLC, Implied, 0, 0);
        codegen_gen(sADC, Immediate, T->len, 0);       // target_lo
        codegen_gen(sEOR, DirectPage, reg_addr(RH - 2), 0);
        codegen_gen(sSTA, DirectPage, reg_addr(RH - 2), 0);
        codegen_gen(sLDA, Immediate, 0, 0);             // target_hi = 0
        codegen_gen(sEOR, DirectPage, reg_addr(RH - 1), 0);
        codegen_gen(sORA, DirectPage, reg_addr(RH - 2), 0);  // Z=1 if match
        RH -= 2;

        if (isguard) {
            if (check) {
                Trap(EQ, 2);  // EQ=match → skip BRK; NE=mismatch → BRK #2
            }
        } else {
            x->orig_type = intType;
            SetCC(x, EQ);
        }
    } else {
        // Pointer-based type test (IS operator or type guard)
        load(x);  // pointer in R[x->r] (addr), R[x->r+1] (bank)
        Set16(1, 1);

        // NIL check: if pointer is zero, skip type test
        codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);
        codegen_gen(sORA, DirectPage, reg_addr(x->r + 1), 0);
        LONGINT nil_skip = emitFwdBranch(sBEQ);  // BEQ → skip to end (Z=1)

        // Load 4-byte tag from [pointer - 4]
        incR(); incR();  // temp pair for addressing AND tag storage
        codegen_gen(sSEC, Implied, 0, 0);
        codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);
        codegen_gen(sSBC, Immediate, 4, 0);
        codegen_gen(sSTA, DirectPage, reg_addr(RH - 2), 0);  // (ptr-4) addr
        codegen_gen(sLDA, DirectPage, reg_addr(x->r + 1), 0);
        codegen_gen(sSBC, Immediate, 0, 0);  // borrow propagation
        codegen_gen(sSTA, DirectPage, reg_addr(RH - 1), 0);  // (ptr-4) bank
        codegen_gen(sLDA, DirectPageIndirectLong, reg_addr(RH - 2), 0);  // tag_lo
        codegen_gen(sPHA, Implied, 0, 0);
        codegen_gen(sLDY, Immediate, 2, 0);
        codegen_gen(sLDA, DirectPageIndirectLongIndexedY, reg_addr(RH - 2), 0);  // tag_hi
        codegen_gen(sSTA, DirectPage, reg_addr(RH - 1), 0);
        codegen_gen(sPLA, Implied, 0, 0);
        codegen_gen(sSTA, DirectPage, reg_addr(RH - 2), 0);  // tag in temp pair

        // Add ancestor offset: 2 + (nofpar-1)*4
        LONGINT offset = 2 + (T->nofpar - 1) * 4;
        codegen_gen(sCLC, Implied, 0, 0);
        codegen_gen(sLDA, DirectPage, reg_addr(RH - 2), 0);
        codegen_gen(sADC, Immediate, offset, 0);
        codegen_gen(sSTA, DirectPage, reg_addr(RH - 2), 0);
        codegen_gen(sLDA, DirectPage, reg_addr(RH - 1), 0);
        codegen_gen(sADC, Immediate, 0, 0);  // carry propagation
        codegen_gen(sSTA, DirectPage, reg_addr(RH - 1), 0);

        // Load 4-byte ancestor
        codegen_gen(sLDA, DirectPageIndirectLong, reg_addr(RH - 2), 0);  // ancestor_lo
        codegen_gen(sPHA, Implied, 0, 0);
        codegen_gen(sLDY, Immediate, 2, 0);
        codegen_gen(sLDA, DirectPageIndirectLongIndexedY, reg_addr(RH - 2), 0);  // ancestor_hi
        codegen_gen(sSTA, DirectPage, reg_addr(RH - 1), 0);
        codegen_gen(sPLA, Implied, 0, 0);
        codegen_gen(sSTA, DirectPage, reg_addr(RH - 2), 0);

        // XOR+ORA compare with target: SB + T->len
        int sb = GetSB(-T->mno);
        codegen_gen(sLDA, DirectPage, sb, 0);
        codegen_gen(sCLC, Implied, 0, 0);
        codegen_gen(sADC, Immediate, T->len, 0);       // target_lo
        codegen_gen(sEOR, DirectPage, reg_addr(RH - 2), 0);
        codegen_gen(sSTA, DirectPage, reg_addr(RH - 2), 0);
        codegen_gen(sLDA, Immediate, 0, 0);             // target_hi = 0
        codegen_gen(sEOR, DirectPage, reg_addr(RH - 1), 0);
        codegen_gen(sORA, DirectPage, reg_addr(RH - 2), 0);  // Z=1 if match
        RH -= 2;  // free temp pair

        patch(nil_skip);  // BEQ target: Z=1 from ORA (NIL → IS returns TRUE)

        if (isguard) {
            if (check) {
                Trap(EQ, 2);  // EQ=match → skip BRK; NE=mismatch → BRK #2
            }
        } else {
            x->orig_type = intType;  // ensure unsigned comparison for SetCC
            SetCC(x, EQ);  // IS result: EQ if types match
            RH -= 2;       // free pointer registers
        }
    }
}

// Boolean operators
void ORG_Not(ORG_Item *x) {
    LONGINT t;
    
    // Convert to condition mode if not already
    if (x->mode != Cond) {
        loadCond(x);
    }
    
    // Negate the condition code (EQ<->NE, MI<->PL, etc.)
    x->r = negated(x->r);
    
    // Swap the TRUE and FALSE branch chains
    t = x->a;
    x->a = x->b;
    x->b = t;
}

/*
  PROCEDURE And1*(VAR x: Item);   (* x := x & *)
  BEGIN
    IF x.mode # Cond THEN loadCond(x) END ;
    Put3(BC, negated(x.r), x.a); x.a := pc-1; FixLink(x.b); x.b := 0
  END And1;
*/
void ORG_And1(ORG_Item *x) {
    if (x->mode != Cond) {
        loadCond(x);
    }
    // Generate branch with negated condition to FALSE chain
    // If x is FALSE, jump to FALSE result (short-circuit)
    emitBranch(negated(x->r), x->orig_type, Fixup, x->a);
    x->a = ORG_pc - 2;  // Save current branch location for FALSE chain (BRL offset field)
    ORG_FixLink(x->b);  // Fix up previous TRUE branches
    x->b = 0;           // Reset TRUE chain
}

/*
  PROCEDURE And2*(VAR x, y: Item);
  BEGIN
    IF y.mode # Cond THEN loadCond(y) END ;
    x.a := merged(y.a, x.a); x.b := y.b; x.r := y.r
  END And2;
*/
void ORG_And2(ORG_Item *x, ORG_Item *y) {
    if (y->mode != Cond) {
        loadCond(y);
    }
    // Merge FALSE chains: if either x or y is FALSE, jump to FALSE result
    x->a = merged(y->a, x->a);
    // Use second operand's result for TRUE chain, condition, and type
    x->b = y->b;
    x->r = y->r;
    x->orig_type = y->orig_type;
}  

/*
  PROCEDURE Or1*(VAR x: Item);   (* x := x OR *)
  BEGIN
    IF x.mode # Cond THEN loadCond(x) END ;
    Put3(BC, x.r, x.b);  x.b := pc-1; FixLink(x.a); x.a := 0
  END Or1;
*/
void ORG_Or1(ORG_Item *x) {
    if (x->mode != Cond) {
        loadCond(x);
    }
    // Generate branch with condition (NOT negated) to TRUE chain
    // If x is TRUE, jump to TRUE result (short-circuit)
    emitBranch(x->r, x->orig_type, Fixup, x->b);
    x->b = ORG_pc - 2;  // Save current branch location for TRUE chain (BRL offset field)
    ORG_FixLink(x->a);  // Fix up previous FALSE branches
    x->a = 0;           // Reset FALSE chain
}

/*
  PROCEDURE Or2*(VAR x, y: Item);
  BEGIN
    IF y.mode # Cond THEN loadCond(y) END ;
    x.a := y.a; x.b := merged(y.b, x.b); x.r := y.r
  END Or2;
*/
void ORG_Or2(ORG_Item *x, ORG_Item *y) {
    if (y->mode != Cond) {
        loadCond(y);
    }
    // Use second operand's FALSE chain
    x->a = y->a;
    // Merge TRUE chains: if either x or y is TRUE, jump to TRUE result
    x->b = merged(y->b, x->b);
    // Use second operand's condition and type
    x->r = y->r;
    x->orig_type = y->orig_type;
}

// Arithmetic operators
void ORG_Neg(ORG_Item *x) {
  if (x->type->form == ORB_Int) {
	Set16(1, 1);
	if (x->mode == ORB_Const) {
	  x->a = -x->a;
	} else {
	  load(x);
	  codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);
	  codegen_gen(sEOR, Immediate, 0xffff, 0);
	  codegen_gen(sCLC, Implied, 0, 0);
	  codegen_gen(sADC, Immediate, 1, 0);
	  codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);
	}
  } else if (x->type->form == ORB_Real) {
	if (x->mode == ORB_Const) {
	  x->a = x->a ^ 0x80000000;
	} else {
	  load(x);
	  Set16(1, 1);
	  codegen_gen(sLDA, DirectPage, reg_addr(x->r + 1), 0);
	  codegen_gen(sEOR, Immediate, 0x8000, 0);
	  codegen_gen(sSTA, DirectPage, reg_addr(x->r + 1), 0);
	}
  } else { // Set
	if (x->mode == ORB_Const) {
	  x->a = -x->a - 1;
	} else {
	  load(x);
	  codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);
	  codegen_gen(sEOR, Immediate, 0xffff, 0);
	  codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);
	}
  }
}

void ORG_AddOp(LONGINT op, ORG_Item *x, ORG_Item *y) {
    int reg_count = 0;
    
    if (op == ORS_plus) {
        if ((x->mode == ORB_Const) && (y->mode == ORB_Const)) {
            x->a = x->a + y->a;
        } else if (x->mode == ORB_Const) {
            // x is constant, y is not yet loaded - must load y first
            load(y);
            if (x->a != 0) {
                // 65C816: Add immediate to register (y = y + x)
                if (y->type->form == ORB_Int) {
                    Set16(1, 1);
                    codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);  // LDA $reg_y
                    codegen_gen(sCLC, Implied, 0, 0);                  // CLC
                    codegen_gen(sADC, Immediate, x->a, 0);             // ADC #constant
                    codegen_gen(sSTA, DirectPage, reg_addr(y->r), 0);  // STA $reg_y
                }
            }
            // Result is in y's register
            x->mode = y->mode;
            x->r = y->r;
        } else if (y->mode == ORB_Const) {
            reg_count += load(x);
            if (y->a != 0) {
                // 65C816: Add immediate to register
			  if (x->type->form == ORB_Int) {
				Set16(1, 1);
				codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);  // LDA $reg
				codegen_gen(sCLC, Implied, 0, 0);                  // CLC
				codegen_gen(sADC, Immediate, y->a, 0);             // ADC #constant
				codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);  // STA $reg
			  }
            }
        } else {
            load(x);
            load(y);
            // 65C816: Add two registers, result to R[RH-2] (like original Oberon)
            if (x->type->form == ORB_Int) {
              int dest_r = RH - 2;
              Set16(1, 1);
              codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);  // LDA $reg_x
              codegen_gen(sCLC, Implied, 0, 0);                  // CLC
              codegen_gen(sADC, DirectPage, reg_addr(y->r), 0);  // ADC $reg_y
              codegen_gen(sSTA, DirectPage, reg_addr(dest_r), 0); // STA $reg_dest
            }
            RH--;
            x->r = RH - 1;
        }
    } else { // minus
        if ((x->mode == ORB_Const) && (y->mode == ORB_Const)) {
            x->a = x->a - y->a;
        } else if (y->mode == ORB_Const) {
            reg_count += load(x);
            if (y->a != 0) {
                // 65C816: Subtract immediate from register
                if (x->type->form == ORB_Int) {
				  Set16(1, 1);
				  codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);  // LDA $reg
				  codegen_gen(sSEC, Implied, 0, 0);                  // SEC
				  codegen_gen(sSBC, Immediate, y->a, 0);             // SBC #constant
				  codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);  // STA $reg
                }
            }
        } else {
            load(x);
            load(y);
            // 65C816: Subtract two registers, result to R[RH-2] (like original Oberon)
            if (x->type->form == ORB_Int) {
              int dest_r = RH - 2;
              Set16(1, 1);
              codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);  // LDA $reg_x
              codegen_gen(sSEC, Implied, 0, 0);                  // SEC
              codegen_gen(sSBC, DirectPage, reg_addr(y->r), 0);  // SBC $reg_y
              codegen_gen(sSTA, DirectPage, reg_addr(dest_r), 0); // STA $reg_dest
            }
            RH--;
            x->r = RH - 1;
        }
    }
}

static LONGINT ORG_log2(LONGINT m, LONGINT *e) {
    *e = 0;
    while ((m % 2) == 0) {
        m = m / 2;
        (*e)++;
    }
    return m;
}

void ORG_MulOp(ORG_Item *x, ORG_Item *y) {
    LONGINT e;
    
    if ((x->mode == ORB_Const) && (y->mode == ORB_Const)) {
        x->a = x->a * y->a;
    } else if ((y->mode == ORB_Const) && (y->a >= 2) && (ORG_log2(y->a, &e) == 1)) {
        load(x);
		Set16(1, 1);
		codegen_gen(sLDX, Immediate, e, 0);
		LONGINT loop_top = ORG_pc;
		codegen_gen(sASL, DirectPage, reg_addr(x->r), 0);
		codegen_gen(sDEX, Implied, 0, 0);
		codegen_gen(sBNE, ProgramCounterRelative, loop_top, 0);
    } else if (y->mode == ORB_Const) {
        load(x);
        load(y);
		Set16(1, 1);
		codegen_gen(sLDA, Immediate, 0, 0);               // Initialize result
		codegen_gen(sLDX, DirectPage, reg_addr(x->r), 0); // MULT1: operand 1
		codegen_gen(sBEQ, ProgramCounterRelative, ORG_pc + 2 + 11, 0);  // if operand 1 is zero, TO DONE
		codegen_gen(sLSR, DirectPage, reg_addr(x->r), 0); // get right bit, operand 1
		codegen_gen(sBCC, ProgramCounterRelative, ORG_pc + 2 + 3, 0);   // if clear, no addition to previous products
		codegen_gen(sCLC, Implied, 0, 0);                 // else add oprd 2 to partial result
		codegen_gen(sADC, DirectPage, reg_addr(y->r), 0);
		codegen_gen(sASL, DirectPage, reg_addr(y->r), 0); // MCAND2: now shift oprd 2 left for poss add next time
		codegen_gen(sBRA, ProgramCounterRelative, ORG_pc + 2 - 15, 0);  // To MULT1
        RH--;
        x->r = RH - 1;
		codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0); // store result
    } else if ((x->mode == ORB_Const) && (x->a >= 2) && (ORG_log2(x->a, &e) == 1)) {
        load(y);
		Set16(1, 1);
		codegen_gen(sLDX, Immediate, e, 0);
		LONGINT loop_top2 = ORG_pc;
		codegen_gen(sASL, DirectPage, reg_addr(y->r), 0);
		codegen_gen(sDEX, Implied, 0, 0);
		codegen_gen(sBNE, ProgramCounterRelative, loop_top2, 0);
        x->mode = Reg;
        x->r = y->r;
    } else if (x->mode == ORB_Const) {
        load(x);
        load(y);
		Set16(1, 1);
		codegen_gen(sLDA, Immediate, 0, 0);               // Initialize result
		codegen_gen(sLDX, DirectPage, reg_addr(x->r), 0); // MULT1: operand 1
		codegen_gen(sBEQ, ProgramCounterRelative, ORG_pc + 2 + 11, 0);  // if operand 1 is zero, TO DONE
		codegen_gen(sLSR, DirectPage, reg_addr(x->r), 0); // get right bit, operand 1
		codegen_gen(sBCC, ProgramCounterRelative, ORG_pc + 2 + 3, 0);   // if clear, no addition to previous products
		codegen_gen(sCLC, Implied, 0, 0);                 // else add oprd 2 to partial result
		codegen_gen(sADC, DirectPage, reg_addr(y->r), 0);
		codegen_gen(sASL, DirectPage, reg_addr(y->r), 0); // MCAND2: now shift oprd 2 left for poss add next time
		codegen_gen(sBRA, ProgramCounterRelative, ORG_pc + 2 - 15, 0);  // To MULT1
        RH--;
        x->r = RH - 1;
		codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0); // store result
    } else {
        load(x);
        load(y);
		Set16(1, 1);
		codegen_gen(sLDA, Immediate, 0, 0);               // Initialize result
		codegen_gen(sLDX, DirectPage, reg_addr(x->r), 0); // MULT1: operand 1
		codegen_gen(sBEQ, ProgramCounterRelative, ORG_pc + 2 + 11, 0);  // if operand 1 is zero, TO DONE
		codegen_gen(sLSR, DirectPage, reg_addr(x->r), 0); // get right bit, operand 1
		codegen_gen(sBCC, ProgramCounterRelative, ORG_pc + 2 + 3, 0);   // if clear, no addition to previous products
		codegen_gen(sCLC, Implied, 0, 0);                 // else add oprd 2 to partial result
		codegen_gen(sADC, DirectPage, reg_addr(y->r), 0);
		codegen_gen(sASL, DirectPage, reg_addr(y->r), 0); // MCAND2: now shift oprd 2 left for poss add next time
		codegen_gen(sBRA, ProgramCounterRelative, ORG_pc + 2 - 15, 0);  // To MULT1
        RH--;
        x->r = RH - 1;
		codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0); // store result
    }
}

// Generate inline unsigned division loop.
// dividend_reg holds dividend (becomes remainder), divisor_reg holds divisor.
// quotient_reg is initialized to 0 and counts iterations.
// After loop: quotient_reg = quotient, dividend_reg = remainder.
static void genDivLoop(int dividend_reg, int divisor_reg, int quotient_reg) {
    Set16(1, 1);
    codegen_gen(sLDA, Immediate, 0, 0);                            // LDA #0
    codegen_gen(sSTA, DirectPage, reg_addr(quotient_reg), 0);      // q = 0
    // LOOP:
    LONGINT loop_top = ORG_pc;
    codegen_gen(sLDA, DirectPage, reg_addr(dividend_reg), 0);      // LDA a
    codegen_gen(sCMP, DirectPage, reg_addr(divisor_reg), 0);       // CMP b
    codegen_gen(sBCC, ProgramCounterRelative, ORG_pc + 2 + 11, 0); // if a < b, EXIT
    codegen_gen(sLDA, DirectPage, reg_addr(dividend_reg), 0);      // LDA a     (2)
    codegen_gen(sSEC, Implied, 0, 0);                              // SEC       (1)
    codegen_gen(sSBC, DirectPage, reg_addr(divisor_reg), 0);       // SBC b     (2)
    codegen_gen(sSTA, DirectPage, reg_addr(dividend_reg), 0);      // a = a - b (2)
    codegen_gen(sINC, DirectPage, reg_addr(quotient_reg), 0);      // q = q + 1 (2)
    codegen_gen(sBRA, ProgramCounterRelative, loop_top, 0);        // BRA LOOP  (2)
    // EXIT:
}

void ORG_DivOp(LONGINT op, ORG_Item *x, ORG_Item *y) {
    LONGINT e;

    if (op == ORS_div) {
        if ((x->mode == ORB_Const) && (y->mode == ORB_Const)) {
            if (y->a > 0) {
                x->a = x->a / y->a;
            } else {
                ORS_Mark("bad divisor");
            }
        } else if ((y->mode == ORB_Const) && (y->a >= 2) && (ORG_log2(y->a, &e) == 1)) {
            load(x);
            // Arithmetic shift right e times (signed divide by power of 2)
            // CMP #$8000 sets carry = sign bit; ROR shifts carry into bit 15
            for (int i = 0; i < e; i++) {
              codegen_gen(sCMP, Immediate, 0x8000, 0);
              codegen_gen(sROR, Implied, 0, 0);
            }
            codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);
        } else if (y->mode == ORB_Const) {
            if (y->a > 0) {
                load(x);
                // Load constant divisor into a register
                Set16(1, 1);
                codegen_gen(sLDA, Immediate, y->a, 0);
                codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);
                int divisor_reg = RH;
                incR();
                int quotient_reg = RH;
                incR();
                genDivLoop(x->r, divisor_reg, quotient_reg);
                // Result (quotient) goes into x's register
                codegen_gen(sLDA, DirectPage, reg_addr(quotient_reg), 0);
                codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);
                RH -= 2;  // Free divisor and quotient registers
            } else {
                ORS_Mark("bad divisor");
            }
        } else {
            load(y);
            if (check) {
                Trap(LE, 6);
            }
            load(x);
            // y->r = divisor, x->r = dividend
            int quotient_reg = RH;
            incR();
            genDivLoop(x->r, y->r, quotient_reg);
            // Copy quotient to y->r (lowest register), free x and quotient regs
            codegen_gen(sLDA, DirectPage, reg_addr(quotient_reg), 0);
            codegen_gen(sSTA, DirectPage, reg_addr(y->r), 0);
            x->r = y->r;
            RH = y->r + 1;
        }
    } else { // mod
        if ((x->mode == ORB_Const) && (y->mode == ORB_Const)) {
            if (y->a > 0) {
                x->a = x->a % y->a;
            } else {
                ORS_Mark("bad modulus");
            }
        } else if ((y->mode == ORB_Const) && (y->a >= 2) && (ORG_log2(y->a, &e) == 1)) {
            load(x);
            // MOD by power of 2 = AND with (divisor - 1)
            Set16(1, 1);
            codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);
            codegen_gen(sAND, Immediate, y->a - 1, 0);
            codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);
        } else if (y->mode == ORB_Const) {
            if (y->a > 0) {
                load(x);
                // Load constant divisor into a register
                Set16(1, 1);
                codegen_gen(sLDA, Immediate, y->a, 0);
                codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);
                int divisor_reg = RH;
                incR();
                int quotient_reg = RH;
                incR();
                genDivLoop(x->r, divisor_reg, quotient_reg);
                // Result (remainder) is already in x->r
                RH -= 2;  // Free divisor and quotient registers
            } else {
                ORS_Mark("bad modulus");
            }
        } else {
            load(y);
            if (check) {
                Trap(LE, 6);
            }
            load(x);
            // y->r = divisor, x->r = dividend (remainder after loop)
            int quotient_reg = RH;
            incR();
            genDivLoop(x->r, y->r, quotient_reg);
            // Copy remainder to y->r (lowest register), free x and quotient regs
            codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);
            codegen_gen(sSTA, DirectPage, reg_addr(y->r), 0);
            x->r = y->r;
            RH = y->r + 1;
        }
    }
}

void ORG_RealOp(INTEGER op, ORG_Item *x, ORG_Item *y) {
    load(x);
    load(y);
    Set16(1, 1);
    // Copy x (operand A) to FP_A workspace
    codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);
    codegen_gen(sSTA, DirectPage, FP_A_LO, 0);
    codegen_gen(sLDA, DirectPage, reg_addr(x->r + 1), 0);
    codegen_gen(sSTA, DirectPage, FP_A_HI, 0);
    // Copy y (operand B) to FP_B workspace
    codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);
    codegen_gen(sSTA, DirectPage, FP_B_LO, 0);
    codegen_gen(sLDA, DirectPage, reg_addr(y->r + 1), 0);
    codegen_gen(sSTA, DirectPage, FP_B_HI, 0);

    if (op == ORS_plus) {
      if (fp_fixup_count[FP_ADD] < maxFPFixups)
        fp_fixups[FP_ADD][fp_fixup_count[FP_ADD]++] = ORG_pc + 1;
      codegen_gen(sJSR, Absolute, 0x0000, 0);
    } else if (op == ORS_minus) {
      // Negate B, then add: FP_B_HI ^= 0x8000
      codegen_gen(sLDA, DirectPage, FP_B_HI, 0);
      codegen_gen(sEOR, Immediate, 0x8000, 0);
      codegen_gen(sSTA, DirectPage, FP_B_HI, 0);
      if (fp_fixup_count[FP_ADD] < maxFPFixups)
        fp_fixups[FP_ADD][fp_fixup_count[FP_ADD]++] = ORG_pc + 1;
      codegen_gen(sJSR, Absolute, 0x0000, 0);
    } else if (op == ORS_times) {
      if (fp_fixup_count[FP_MUL] < maxFPFixups)
        fp_fixups[FP_MUL][fp_fixup_count[FP_MUL]++] = ORG_pc + 1;
      codegen_gen(sJSR, Absolute, 0x0000, 0);
    } else if (op == ORS_rdiv) {
      if (fp_fixup_count[FP_DIV] < maxFPFixups)
        fp_fixups[FP_DIV][fp_fixup_count[FP_DIV]++] = ORG_pc + 1;
      codegen_gen(sJSR, Absolute, 0x0000, 0);
    }

    // Copy result back from FP_A to R[x->r], R[x->r+1]
    codegen_gen(sLDA, DirectPage, FP_A_LO, 0);
    codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);
    codegen_gen(sLDA, DirectPage, FP_A_HI, 0);
    codegen_gen(sSTA, DirectPage, reg_addr(x->r + 1), 0);

    RH -= 2;
    x->r = RH - 2;
}

// Set operators
void ORG_Singleton(ORG_Item *x) {
    if (x->mode == ORB_Const) {
        x->a = 1L << x->a;
    } else {
        load(x);
        // 65C816: Compute 1 << x->r using shift loop
        // LDA #1; LDX reg; BEQ skip; loop: ASL A; DEX; BNE loop; skip: STA reg
        Set16(1, 1);
        codegen_gen(sLDA, Immediate, 1, 0);             // LDA #1
        codegen_gen(sLDX, DirectPage, reg_addr(x->r), 0); // LDX $reg (shift count)
        LONGINT skip = ORG_pc + 2 + 4;                  // BEQ past ASL+DEX+BNE
        codegen_gen(sBEQ, ProgramCounterRelative, skip, 0); // BEQ skip
        LONGINT loop_top = ORG_pc;
        codegen_gen(sASL, Accumulator, 0, 0);            // ASL A
        codegen_gen(sDEX, Implied, 0, 0);                // DEX
        codegen_gen(sBNE, ProgramCounterRelative, loop_top, 0); // BNE loop
        // skip:
        codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0); // STA $reg
    }
}

void ORG_Set(ORG_Item *x, ORG_Item *y) {
    if ((x->mode == ORB_Const) && (y->mode == ORB_Const)) {
        if (x->a <= y->a) {
            x->a = (2L << y->a) - (1L << x->a);
        } else {
            x->a = 0;
        }
    } else {
        // {x..y} = (0xFFFF << x) AND NOT(0xFFFE << y)
        // Part 1: compute 0xFFFF << x into x->r
        if ((x->mode == ORB_Const) && (x->a <= 15)) {
            load(x);  // need a register
            Set16(1, 1);
            codegen_gen(sLDA, Immediate, (int)(0xFFFF << x->a) & 0xFFFF, 0);
            codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);
        } else {
            load(x);
            // shift loop: LDA #$FFFF; LDX reg; BEQ skip; ASL A; DEX; BNE loop; skip: STA reg
            Set16(1, 1);
            codegen_gen(sLDA, Immediate, 0xFFFF, 0);
            codegen_gen(sLDX, DirectPage, reg_addr(x->r), 0);
            LONGINT skip1 = ORG_pc + 2 + 4;
            codegen_gen(sBEQ, ProgramCounterRelative, skip1, 0);
            LONGINT loop1 = ORG_pc;
            codegen_gen(sASL, Accumulator, 0, 0);
            codegen_gen(sDEX, Implied, 0, 0);
            codegen_gen(sBNE, ProgramCounterRelative, loop1, 0);
            // skip1:
            codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);
        }

        // Part 2: compute NOT(0xFFFE << y) into y->r
        if ((y->mode == ORB_Const) && (y->a < 15)) {
            LONGINT mask = ~((LONGINT)0xFFFE << y->a) & 0xFFFF;
            Set16(1, 1);
            codegen_gen(sLDA, Immediate, (int)mask, 0);
            codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);
            y->mode = Reg;
            y->r = RH;
            incR();
        } else {
            load(y);
            // shift loop: LDA #$FFFE; LDX reg; BEQ skip; ASL A; DEX; BNE loop; skip: EOR #$FFFF; STA reg
            Set16(1, 1);
            codegen_gen(sLDA, Immediate, 0xFFFE, 0);
            codegen_gen(sLDX, DirectPage, reg_addr(y->r), 0);
            LONGINT skip2 = ORG_pc + 2 + 4;
            codegen_gen(sBEQ, ProgramCounterRelative, skip2, 0);
            LONGINT loop2 = ORG_pc;
            codegen_gen(sASL, Accumulator, 0, 0);
            codegen_gen(sDEX, Implied, 0, 0);
            codegen_gen(sBNE, ProgramCounterRelative, loop2, 0);
            // skip2:
            codegen_gen(sEOR, Immediate, 0xFFFF, 0);
            codegen_gen(sSTA, DirectPage, reg_addr(y->r), 0);
        }

        // Part 3: AND the two parts together
        if (x->mode == ORB_Const) {
            // x was const, already loaded into x->r above
            x->mode = Reg;
        }
        codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);
        codegen_gen(sAND, DirectPage, reg_addr(y->r), 0);
        codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);
        RH--;
        x->r = RH - 1;
    }
}

void ORG_In(ORG_Item *x, ORG_Item *y) {
    // x IN y: test if bit x is set in set y
    // Build mask (1 << x), AND with y, test NE
    load(y);
    Set16(1, 1);
    if (x->mode == ORB_Const) {
        // Constant bit position: AND with compile-time mask
        codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);
        codegen_gen(sAND, Immediate, (int)(1L << x->a) & 0xFFFF, 0);
        codegen_gen(sSTA, DirectPage, reg_addr(y->r), 0);
        RH--;
    } else {
        load(x);
        // Variable bit position: shift loop to build mask 1 << x
        codegen_gen(sLDA, Immediate, 1, 0);
        codegen_gen(sLDX, DirectPage, reg_addr(x->r), 0);
        LONGINT skip = ORG_pc + 2 + 4;
        codegen_gen(sBEQ, ProgramCounterRelative, skip, 0);
        LONGINT loop_top = ORG_pc;
        codegen_gen(sASL, Accumulator, 0, 0);
        codegen_gen(sDEX, Implied, 0, 0);
        codegen_gen(sBNE, ProgramCounterRelative, loop_top, 0);
        // skip: A = 1 << x, AND with set y
        codegen_gen(sAND, DirectPage, reg_addr(y->r), 0);
        codegen_gen(sSTA, DirectPage, reg_addr(y->r), 0);
        RH -= 2;
    }
    SetCC(x, NE);
}

void ORG_SetOp(LONGINT op, ORG_Item *x, ORG_Item *y) {
    if ((x->mode == ORB_Const) && (y->mode == ORB_Const)) {
        // Use direct bit operations instead of SET type
        if (op == ORS_plus) {
            x->a = x->a | y->a;
        } else if (op == ORS_minus) {
            x->a = x->a & ~y->a;
        } else if (op == ORS_times) {
            x->a = x->a & y->a;
        } else if (op == ORS_rdiv) {
            x->a = x->a ^ y->a;
        }
    } else if (y->mode == ORB_Const) {
        load(x);
        if (op == ORS_plus) {
		  codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);
		  codegen_gen(sORA, Immediate, y->a, 0);
		  codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);
        } else if (op == ORS_minus) {
		  codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);
		  codegen_gen(sAND, Immediate, ~y->a & 0xFFFF, 0);
		  codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);
        } else if (op == ORS_times) {
		  codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);
		  codegen_gen(sAND, Immediate, y->a, 0);
		  codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);
        } else if (op == ORS_rdiv) {
		  codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);
		  codegen_gen(sEOR, Immediate, y->a, 0);
		  codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);
        }
    } else {
        load(x);
        load(y);
        if (op == ORS_plus) {
		  codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);
		  codegen_gen(sORA, DirectPage, reg_addr(y->r), 0);
		  codegen_gen(sSTA, DirectPage, reg_addr(RH-2), 0);
        } else if (op == ORS_minus) {
		  codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);
		  codegen_gen(sEOR, Immediate, 0xFFFF, 0);
		  codegen_gen(sAND, DirectPage, reg_addr(x->r), 0);
		  codegen_gen(sSTA, DirectPage, reg_addr(RH-2), 0);
        } else if (op == ORS_times) {
		  codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);
		  codegen_gen(sAND, DirectPage, reg_addr(y->r), 0);
		  codegen_gen(sSTA, DirectPage, reg_addr(RH-2), 0);
        } else if (op == ORS_rdiv) {
		  codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);
		  codegen_gen(sEOR, DirectPage, reg_addr(y->r), 0);
		  codegen_gen(sSTA, DirectPage, reg_addr(RH-2), 0);
        }
        RH--;
        x->r = RH - 1;
    }
}

// Relation operators
/*
  PROCEDURE IntRelation*(op: INTEGER; VAR x, y: Item);   (* x := x < y *)
  BEGIN
    IF (y.mode = ORB.Const) & (y.type.form # ORB.Proc) THEN
      load(x);
      IF (y.a # 0) OR ~(op IN {ORS.eql, ORS.neq}) OR (code[pc-1] DIV 40000000H # -2) THEN Put1a(Cmp, x.r, x.r, y.a) END ;
      DEC(RH)
    ELSE
      IF (x.mode = Cond) OR (y.mode = Cond) THEN ORS.Mark("not implemented") END ;
      load(x); load(y); Put0(Cmp, x.r, x.r, y.r); DEC(RH, 2)
    END ;
    SetCC(x, relmap[op - ORS.eql])
  END IntRelation;
*/
void ORG_IntRelation(INTEGER op, ORG_Item *x, ORG_Item *y) {
    BOOLEAN is_pointer = (x->type->form == ORB_Pointer) || (x->type->form == ORB_NilTyp) || (x->type->form == ORB_Proc);
    BOOLEAN use_8bit = !is_pointer && ((x->type->form == ORB_Char) || (x->type->form == ORB_Byte) || (x->type->form == ORB_Bool));
    BOOLEAN use_signed = !is_pointer && !use_8bit && (x->type->form == ORB_Int);

    if (is_pointer) {
        // Pointer comparison: 4-byte (addr + bank), only EQ/NE supported
        Set16(1, 1);
        if ((y->mode == ORB_Const) && (y->a == 0)) {
            // Compare with NIL (constant 0): ORA both words, test Z flag
            load(x);
            codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);      // LDA addr
            codegen_gen(sORA, DirectPage, reg_addr(x->r + 1), 0);  // ORA bank
            RH -= 2;  // free both pointer registers
        } else {
            // Compare two pointers: compare addr words, then bank words
            load(x);
            load(y);
            // Pattern: CMP addr words, BNE done, CMP bank words, done:
            // After this sequence, Z flag reflects full 4-byte equality
            codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);      // LDA x.addr
            codegen_gen(sCMP, DirectPage, reg_addr(y->r), 0);      // CMP y.addr
            codegen_gen(sBNE, ProgramCounterRelative, ORG_pc + 2 + 4, 0);  // BNE skip (addr differs)
            codegen_gen(sLDA, DirectPage, reg_addr(x->r + 1), 0);  // LDA x.bank
            codegen_gen(sCMP, DirectPage, reg_addr(y->r + 1), 0);  // CMP y.bank
            // skip: Z flag is correct
            RH -= 4;  // free all 4 pointer registers
        }
        SetCC(x, relmap[op - ORS_eql]);
        return;
    }

    if (use_8bit) {
        Set8(1, 0);  // Switch to 8-bit accumulator mode
    }

    if ((y->mode == ORB_Const) && (y->type->form != ORB_Proc)) {
        load(x);
        if ((y->a != 0) || ((op != ORS_eql) && (op != ORS_neq))) {
            // 65C816: Compare with immediate value
            codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);  // LDA $reg_x

            if (use_signed && (op == ORS_lss || op == ORS_geq || op == ORS_leq || op == ORS_gtr)) {
                // For signed comparisons of 16-bit integers, use SBC instead of CMP
                codegen_gen(sSEC, Implied, 0, 0);               // SEC (set carry for subtraction)
                codegen_gen(sSBC, Immediate, y->a, 0);          // SBC #immediate
            } else {
                // For unsigned comparisons or EQ/NE, use CMP
                codegen_gen(sCMP, Immediate, y->a, 0);          // CMP #immediate
            }
        }
        RH--;
    } else {
        if ((x->mode == Cond) || (y->mode == Cond)) {
            ORS_Mark("not implemented");
        }
        load(x);
        load(y);
        // 65C816: Compare two registers
        codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);  // LDA $reg_x

        if (use_signed && (op == ORS_lss || op == ORS_geq || op == ORS_leq || op == ORS_gtr)) {
            // For signed comparisons of 16-bit integers, use SBC instead of CMP
            codegen_gen(sSEC, Implied, 0, 0);               // SEC (set carry for subtraction)
            codegen_gen(sSBC, DirectPage, reg_addr(y->r), 0);  // SBC $reg_y
        } else {
            // For unsigned comparisons or EQ/NE, use CMP
            codegen_gen(sCMP, DirectPage, reg_addr(y->r), 0);  // CMP $reg_y
        }
        RH -= 2;
    }

    if (use_8bit) {
        Set16(1, 1);  // Switch back to 16-bit accumulator mode
    }

    SetCC(x, relmap[op - ORS_eql]);
}

void ORG_RealRelation(INTEGER op, ORG_Item *x, ORG_Item *y) {
    load(x);
    Set16(1, 1);
    // Copy x to FP_A
    codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);
    codegen_gen(sSTA, DirectPage, FP_A_LO, 0);
    codegen_gen(sLDA, DirectPage, reg_addr(x->r + 1), 0);
    codegen_gen(sSTA, DirectPage, FP_A_HI, 0);
    if ((y->mode == ORB_Const) && (y->a == 0)) {
        // Compare against 0.0: just zero FP_B
        codegen_gen(sSTZ, DirectPage, FP_B_LO, 0);
        codegen_gen(sSTZ, DirectPage, FP_B_HI, 0);
        RH -= 2;  // free x's 2 registers
    } else {
        load(y);
        // Copy y to FP_B
        codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);
        codegen_gen(sSTA, DirectPage, FP_B_LO, 0);
        codegen_gen(sLDA, DirectPage, reg_addr(y->r + 1), 0);
        codegen_gen(sSTA, DirectPage, FP_B_HI, 0);
        RH -= 4;  // free x's 2 + y's 2 registers
    }
    // JSR fp_cmp
    if (fp_fixup_count[FP_CMP] < maxFPFixups)
      fp_fixups[FP_CMP][fp_fixup_count[FP_CMP]++] = ORG_pc + 1;
    codegen_gen(sJSR, Absolute, 0x0000, 0);
    // FCMP returns -1/0/+1 in FP_A_LO; load it to set CPU flags
    codegen_gen(sLDA, DirectPage, FP_A_LO, 0);
    // SetCC sets orig_type = x->type, so override AFTER SetCC
    SetCC(x, relmap[op - ORS_eql]);
    // Use intType for orig_type so emitBranch uses signed comparison paths
    x->orig_type = intType;
}

void ORG_StringRelation(INTEGER op, ORG_Item *x, ORG_Item *y) {
    if (x->type->form == ORB_String) {
        loadStringAdr(x);
    } else {
        loadAdr(x);
    }
    
    if (y->type->form == ORB_String) {
        loadStringAdr(y);
    } else {
        loadAdr(y);
    }
    
    // RISC: Put2(Ldr + 1, RH, x->r, 0);
    // RISC: Put1(Add, x->r, x->r, 1);
    // RISC: Put2(Ldr + 1, RH + 1, y->r, 0);
    // RISC: Put1(Add, y->r, y->r, 1);
    // RISC: Put0(Cmp, RH + 2, RH, RH + 1);
    // RISC: Put3(BC, NE, 2);
    // RISC: Put1(Cmp, RH + 2, RH, 0);
    // RISC: Put3(BC, NE, -8);
    RH -= 2;
    SetCC(x, relmap[op - ORS_eql]);
}

// Assignment operations
void ORG_StrToChar(ORG_Item *x) {
    x->type = charType;
    x->a = str[x->a];
}

void ORG_Store(ORG_Item *x, ORG_Item *y) {
    load(y);
    
    if (x->mode == ORB_Var) {
        if (x->r > 0) {
            // 65C816: Store to stack-based local variable with type conversion
            if (y->mode == Reg) {
                if (x->type->form == ORB_Pointer || x->type->form == ORB_NilTyp || x->type->form == ORB_Real || x->type->form == ORB_Proc) {
                    // 4-byte store: (pointer, proc, or REAL) from 2 registers
                    Set16(1, 1);
                    codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);     // LDA low word
                    codegen_gen(sSTA, StackRelative, x->a + frame, 0);    // STA offset,S
                    codegen_gen(sLDA, DirectPage, reg_addr(y->r + 1), 0); // LDA high word
                    codegen_gen(sSTA, StackRelative, x->a + 2 + frame, 0); // STA offset+2,S
                    RH--;  // free extra register
                } else if (x->type->size == 1 && y->type->size == 1) {
                    // BYTE to BYTE store (no conversion needed)
                    Set8(1, 0);
                    codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);     // LDA $reg
                    codegen_gen(sSTA, StackRelative, x->a + frame, 0);    // STA x->a,S (8-bit)
                    Set16(1, 0);
                } else if (x->type->size == 1 && y->type->size > 1) {
                    // INTEGER to BYTE store (truncate to low byte)
                    Set8(1, 0);
                    codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);     // LDA $reg
                    codegen_gen(sSTA, StackRelative, x->a + frame, 0);    // STA x->a,S (8-bit)
                    Set16(1, 0);
                } else if (x->type->size > 1 && y->type->size == 1) {
                    // BYTE to INTEGER store (zero-extend)
                    Set16(1, 0);
                    codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);     // LDA $reg (already zero-extended from load)
                    codegen_gen(sSTA, StackRelative, x->a + frame, 0);    // STA x->a,S (16-bit)
                    Set16(1, 0);
                } else {
                    // INTEGER to INTEGER store (no conversion needed)
                    Set16(1, 0);
                    codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);     // LDA $reg
                    codegen_gen(sSTA, StackRelative, x->a + frame, 0);    // STA x->a,S (16-bit)
                    Set16(1, 0);
                }
            }
        } else {
            // 65C816: Store register value to module global variable with type conversion
            int sb = GetSB(x->r);
            if (y->mode == Reg) {
                if (x->type->form == ORB_Pointer || x->type->form == ORB_NilTyp || x->type->form == ORB_Real || x->type->form == ORB_Proc) {
                    // 4-byte store: (pointer, proc, or REAL) from 2 registers
                    Set16(1, 1);
                    codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);     // LDA low word
                    codegen_gen(sLDY, Immediate, x->a, 0);
                    codegen_gen(sSTA, DirectPageIndirectIndexedY, sb, 0);
                    codegen_gen(sLDA, DirectPage, reg_addr(y->r + 1), 0); // LDA high word
                    codegen_gen(sLDY, Immediate, x->a + 2, 0);
                    codegen_gen(sSTA, DirectPageIndirectIndexedY, sb, 0);
                    RH--;  // free extra register
                } else if (x->type->size == 1 && y->type->size == 1) {
                    // BYTE to BYTE store (no conversion needed)
                    Set8(1, 0);
                    codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);
                    codegen_gen(sLDY, Immediate, x->a, 0);
                    codegen_gen(sSTA, DirectPageIndirectIndexedY, sb, 0);
                    Set16(1, 0);
                } else if (x->type->size == 1 && y->type->size > 1) {
                    // INTEGER to BYTE store (truncate to low byte)
                    Set8(1, 0);
                    codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);
                    codegen_gen(sLDY, Immediate, x->a, 0);
                    codegen_gen(sSTA, DirectPageIndirectIndexedY, sb, 0);
                    Set16(1, 0);
                } else if (x->type->size > 1 && y->type->size == 1) {
                    // BYTE to INTEGER store (zero-extend)
                    // load() already zero-extends BYTE to 16-bit, so just do 16-bit store
                    Set16(1, 1);
                    codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);
                    codegen_gen(sLDY, Immediate, x->a, 0);
                    codegen_gen(sSTA, DirectPageIndirectIndexedY, sb, 0);
                } else {
                    // INTEGER to INTEGER store (no conversion needed)
                    Set16(1, 1);
                    codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);
                    codegen_gen(sLDY, Immediate, x->a, 0);
                    codegen_gen(sSTA, DirectPageIndirectIndexedY, sb, 0);
                }
            }
        }
    } else if (x->mode == ORB_Par) {
        // 65C816: Store to VAR parameter - load the 3-byte pointer from stack
        // into temp DP registers, then store through it using indirect long

        if (y->mode == Reg) {
            Set16(1, 1);
            // Load 3-byte pointer (address + bank) from stack into temp registers
            codegen_gen(sLDA, StackRelative, x->a + frame, 0);      // LDA offset,S (address)
            codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);          // STA $temp (address lo/hi)
            codegen_gen(sLDA, StackRelative, x->a + 2 + frame, 0);   // LDA offset+2,S (bank)
            codegen_gen(sSTA, DirectPage, reg_addr(RH + 1), 0);      // STA $temp+1 (bank in lo byte)

            // Store value through the pointer
            // Apply field offset x->b if nonzero (e.g., record field through VAR param)
            if (x->type->form == ORB_Pointer || x->type->form == ORB_NilTyp || x->type->form == ORB_Real || x->type->form == ORB_Proc) {
                // 4-byte store through VAR param: store both words
                codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);        // LDA low word
                codegen_gen(sLDY, Immediate, x->b, 0);
                codegen_gen(sSTA, DirectPageIndirectLongIndexedY, reg_addr(RH), 0);
                codegen_gen(sLDA, DirectPage, reg_addr(y->r + 1), 0);    // LDA high word
                codegen_gen(sLDY, Immediate, x->b + 2, 0);
                codegen_gen(sSTA, DirectPageIndirectLongIndexedY, reg_addr(RH), 0);
                RH--;  // free extra register
            } else if (x->type->size == 1) {
                Set8(1, 0);
                codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);
                if (x->b != 0) {
                    codegen_gen(sLDY, Immediate, x->b, 0);
                    codegen_gen(sSTA, DirectPageIndirectLongIndexedY, reg_addr(RH), 0);
                } else {
                    codegen_gen(sSTA, DirectPageIndirectLong, reg_addr(RH), 0);
                }
                Set16(1, 0);
            } else {
                codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);        // LDA value
                if (x->b != 0) {
                    codegen_gen(sLDY, Immediate, x->b, 0);
                    codegen_gen(sSTA, DirectPageIndirectLongIndexedY, reg_addr(RH), 0);
                } else {
                    codegen_gen(sSTA, DirectPageIndirectLong, reg_addr(RH), 0); // STA [$temp]
                }
            }
        }
    } else if (x->mode == RegI) {
        // 65C816: Store to register indirect (uses long indirect: [$dp] or [$dp],Y)
        if (y->mode == Reg) {
            if (x->type->form == ORB_Pointer || x->type->form == ORB_NilTyp || x->type->form == ORB_Real || x->type->form == ORB_Proc) {
                // 4-byte store through RegI: store both words (pointer, proc, or REAL)
                Set16(1, 1);
                codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);  // LDA addr word
                if (x->a == 0) {
                    codegen_gen(sSTA, DirectPageIndirectLong, reg_addr(x->r), 0);
                } else {
                    codegen_gen(sLDY, Immediate, x->a, 0);
                    codegen_gen(sSTA, DirectPageIndirectLongIndexedY, reg_addr(x->r), 0);
                }
                codegen_gen(sLDA, DirectPage, reg_addr(y->r + 1), 0);  // LDA bank word
                codegen_gen(sLDY, Immediate, x->a + 2, 0);
                codegen_gen(sSTA, DirectPageIndirectLongIndexedY, reg_addr(x->r), 0);
                RH--;  // free extra bank register from y
            } else if (x->type->size == 1) {
                // Byte store through long indirect
                Set8(1, 0);
                codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);  // LDA $reg
                if (x->a == 0) {
                    codegen_gen(sSTA, DirectPageIndirectLong, reg_addr(x->r), 0);
                } else {
                    codegen_gen(sLDY, Immediate, x->a, 0);
                    codegen_gen(sSTA, DirectPageIndirectLongIndexedY, reg_addr(x->r), 0);
                }
                Set16(1, 0);
            } else {
                // Word store through long indirect
                Set16(1, 1);
                codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);  // LDA $reg
                if (x->a == 0) {
                    codegen_gen(sSTA, DirectPageIndirectLong, reg_addr(x->r), 0);
                } else {
                    codegen_gen(sLDY, Immediate, x->a, 0);
                    codegen_gen(sSTA, DirectPageIndirectLongIndexedY, reg_addr(x->r), 0);
                }
            }
        }
        RH -= 2;  // free x->r (addr) and x->r+1 (bank register)
    } else {
        ORS_Mark("bad mode in Store");
    }
    RH--;  // free y->r (source value register)
}

void ORG_StoreStruct(ORG_Item *x, ORG_Item *y) {
    LONGINT s;
    int word_count, dst_reg, src_reg, loop_top;

    if (y->type->size != 0) {
        loadAdr(x);
        loadAdr(y);
        dst_reg = reg_addr(x->r);
        src_reg = reg_addr(y->r);

        if ((x->type->form == ORB_Array) && (x->type->len > 0)) {
            if (y->type->len >= 0) {
                if (x->type->size == y->type->size) {
                    s = y->type->size;
                } else {
                    ORS_Mark("different length/size, not implemented");
                    RH = 0;
                    return;
                }
            } else {
                ORS_Mark("open array assignment not implemented");
                RH = 0;
                return;
            }
        } else if (x->type->form == ORB_Record) {
            s = x->type->size;
        } else {
            ORS_Mark("inadmissible assignment");
            RH = 0;
            return;
        }

        // 65C816: Word-copy loop using (dp),Y indirect addressing
        word_count = (s + 1) / 2;
        Set16(1, 1);
        codegen_gen(sLDY, Immediate, 0, 0);                                 // LDY #0
        codegen_gen(sLDX, Immediate, word_count, 0);                         // LDX #word_count
        loop_top = ORG_pc;
        codegen_gen(sLDA, DirectPageIndirectIndexedY, src_reg, 0);           // LDA (src),Y
        codegen_gen(sSTA, DirectPageIndirectIndexedY, dst_reg, 0);           // STA (dst),Y
        codegen_gen(sINY, Implied, 0, 0);                                    // INY
        codegen_gen(sINY, Implied, 0, 0);                                    // INY
        codegen_gen(sDEX, Implied, 0, 0);                                    // DEX
        codegen_gen(sBNE, ProgramCounterRelative, loop_top, 0);              // BNE loop
    }
    RH = 0;
}

void ORG_CopyString(ORG_Item *x, ORG_Item *y) {
    LONGINT len;

    loadAdr(x);
    len = x->type->len;
    
    if (len >= 0) {
        if (len < y->b) {
            ORS_Mark("string too long");
        }
    } else if (check) {
	  // ToDo:
    // RISC: Put2(Ldr, RH, SP, x->a + 4);
    // RISC: Put1(Cmp, RH, RH, y->b);
        Trap(LT, 3);
    }
    
    loadStringAdr(y);  // Load source string address
    
    // 65C816 string copy implementation using loop with Y as index counter
    // Simpler approach: use Y as index, load addresses into other registers
    
    Set8(1, 0);   // 8-bit accumulator for byte operations
    Set16(0, 1);  // 16-bit index registers
    
    // Initialize Y register to 0 (index counter)
    codegen_gen(sLDY, Immediate, 0, 0);  // LDY #0
    
    // Mark loop start for branch target
    LONGINT loop_start = ORG_pc;
    
    // Load byte from source[Y] using indirect indexed addressing
    codegen_gen(sLDA, DirectPageIndirectIndexedY, reg_addr(y->r), 0);  // LDA (src_ptr),Y
    
    // Store byte to destination[Y] using indirect indexed addressing  
    codegen_gen(sSTA, DirectPageIndirectIndexedY, reg_addr(x->r), 0);  // STA (dst_ptr),Y
    
    // Test for null terminator (zero)  
    // BEQ needs to skip: STA (2 bytes) + INY (1 byte) + BRA (2 bytes) = 5 bytes
    codegen_gen(sBEQ, ProgramCounterRelative, ORG_pc + 2 + 3, 0);  // BEQ to exit (skip increment)
    
    // Increment Y (index counter)
    codegen_gen(sINY, Implied, 0, 0);                      // INY
    
    // Branch back to loop start
    codegen_gen(sBRA, ProgramCounterRelative, loop_start, 0);  // BRA loop_start
    
    // Exit point - null terminator already stored by loop condition (no extra store needed)
    
    RH -= 3;      // Clean up: loadAdr(x) +2, loadStringAdr(y) +1, total 3 registers used
}

// Parameter operations
void ORG_OpenArrayParam(ORG_Item *x) {
    loadAdr(x);
    // Note: loadAdr increments RH by 2, so x->r points to the first register (address)
    // and x->r + 1 contains the bank byte (0). We need to store the length in the next register.
    
    if (x->type->len >= 0) {
        // 65C816: Load array length for fixed arrays passed to open array parameters
        Set16(1, 1);
        codegen_gen(sLDA, Immediate, x->type->len, 0);        // LDA #array_length
        codegen_gen(sSTA, DirectPage, reg_addr(x->r + 2), 0); // STA $reg+2 (next available register)
    } else {
        // 65C816: Load array length for open arrays passed to open array parameters
        // Load the length from the stack frame (x->a + 2 + frame)
        Set16(1, 1);
        codegen_gen(sLDA, StackRelative, x->a + 2 + frame, 0);  // LDA x->a + 2 + frame,S
        codegen_gen(sSTA, DirectPage, reg_addr(x->r + 2), 0);   // STA $reg+2 (next available register)
    }
    incR(); // Allocate the length register
}

void ORG_VarParam(ORG_Item *x, ORB_Type *ftype) {
    INTEGER xmd = x->mode;
    
    // Check if this is a local variable - implement 24-bit address calculation
    if (x->mode == ORB_Var && x->r > 0) {
        // 65C816: Calculate 24-bit address of local variable using stack pointer
        Set16(1, 1);
        codegen_gen(sTSC, Implied, 0, 0);                       // TSC - get stack pointer
        codegen_gen(sCLC, Implied, 0, 0);                       // CLC - clear carry for addition
        codegen_gen(sADC, Immediate, x->a + frame, 0);          // ADC #offset+frame - add local var offset
        codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);         // STA $reg - store calculated address

        x->r = RH;
        x->mode = Reg;
        incR();

        // Store 16-bit 0 to define this as being in bank 0, where the stack resides
        codegen_gen(sLDA, Immediate, 0, 0);                     // LDA #0
        codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);         // STA $reg (store 0)
        incR();
    } else if (x->mode == ORB_Var && x->r <= 0) {
        int sb = GetSB(x->r);
        Set16(1, 1);
        // Compute address: SB_base + offset
        codegen_gen(sLDA, DirectPage, sb, 0);                    // LDA SB (base address)
        if (x->a != 0) {
            codegen_gen(sCLC, Implied, 0, 0);                    // CLC
            codegen_gen(sADC, Immediate, x->a, 0);               // ADC #offset
        }
        codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);          // STA $reg (16-bit address)

        // Store data bank byte (0) in second register
        codegen_gen(sLDA, Immediate, 0, 0);                      // LDA #0
        codegen_gen(sSTA, DirectPage, reg_addr(RH + 1), 0);     // STA $reg+1 (data bank = 0)
        
        x->r = RH;
        x->mode = Reg;
        incR();  // Allocate first register
        incR();  // Allocate second register for 24-bit value
    } else {
        // For other cases (parameters, etc.), use original loadAdr approach
        loadAdr(x);
    }
    
    if ((ftype->form == ORB_Array) && (ftype->len < 0)) {
        // VAR open arrays: use same layout as ORG_OpenArrayParam
        if (x->type->len >= 0) {
            // 65C816: Load array length for fixed arrays passed to VAR open array parameters
            Set16(1, 1);
            codegen_gen(sLDA, Immediate, x->type->len, 0);        // LDA #array_length
            codegen_gen(sSTA, DirectPage, reg_addr(x->r + 2), 0); // STA $reg+2 (same as ORG_OpenArrayParam)
        } else {
            // 65C816: Load array length for open arrays passed to VAR open array parameters
            // Load the length from the stack frame at offset +4 (length is at $05,S in the parameter layout)
            Set16(1, 1);
            codegen_gen(sLDA, StackRelative, x->a + 4 + frame, 0);  // LDA x->a + 4 + frame,S
            codegen_gen(sSTA, DirectPage, reg_addr(x->r + 2), 0);   // STA $reg+2 (same as ORG_OpenArrayParam)
        }
        incR(); // Allocate the length register
    } else if (ftype->form == ORB_Record) {
        // VAR record param: pass 4-byte type tag (2 registers)
        Set16(1, 1);
        if (xmd == ORB_Par) {
            // Source is already a VAR param — forward existing 4-byte tag from stack
            codegen_gen(sLDA, StackRelative, x->a + 4 + frame, 0);  // tag_lo from caller's frame
            codegen_gen(sSTA, DirectPage, reg_addr(x->r + 2), 0);
            codegen_gen(sLDA, StackRelative, x->a + 6 + frame, 0);  // tag_hi from caller's frame
            codegen_gen(sSTA, DirectPage, reg_addr(x->r + 3), 0);
        } else {
            // Source is a direct variable — compute absolute tag: SB + T->len
            int sb = GetSB(-x->type->mno);
            codegen_gen(sLDA, DirectPage, sb, 0);
            codegen_gen(sCLC, Implied, 0, 0);
            codegen_gen(sADC, Immediate, x->type->len, 0);
            codegen_gen(sSTA, DirectPage, reg_addr(x->r + 2), 0);   // tag_lo
            codegen_gen(sSTZ, DirectPage, reg_addr(x->r + 3), 0);   // tag_hi = 0
        }
        incR(); incR();  // 2 registers for 4-byte tag
    }
}

void ORG_ValueParam(ORG_Item *x) {
    load(x);
}

void ORG_StringParam(ORG_Item *x) {
    // Load 4-byte string address like loadAdr for global string constants
    Set16(1, 1);
	//    LONGINT string_addr = MODULE_VAR_BASE + ORG_varsize + x->a;
    
    // Load lower 16 bits of address into RH
    codegen_gen(sLDA, DirectPage, SB_DP, 0);     // LDA #string_address_low
	codegen_gen(sCLC, Implied, 0, 0);
	codegen_gen(sADC, Immediate, ORG_varsize + x->a, 0);
    codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);            // STA $reg
    
    // Load upper 16 bits of address into RH+1 
    // codegen_gen(sLDA, Immediate, (string_addr >> 16) & 0xFFFF, 0);  // LDA #string_address_high
    codegen_gen(sSTZ, DirectPage, reg_addr(RH + 1), 0);             // STA $reg+1
    
    x->mode = Reg;
    x->r = RH;
    incR(); // Allocate address register (low)
    incR(); // Allocate address register (high)
    
    // Load string length into next register (RH+2)
    Set16(1, 1);
    codegen_gen(sLDA, Immediate, x->b, 0);                     // LDA #string_length
    codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);            // STA $reg+2
    incR(); // Allocate length register
}

// For statement operations
void ORG_For0(ORG_Item *x, ORG_Item *y) {
    (void)x;
    load(y);
}

void ORG_For1(ORG_Item *x, ORG_Item *y, ORG_Item *z, ORG_Item *w, LONGINT *L) {
    // Compare loop variable with limit
    BOOLEAN use_signed = (y->type->form == ORB_Int) && (y->type->size == 2);
    if (z->mode == ORB_Const) {
        // Compare y register with immediate constant z->a
        load(y);
        if (z->type->size == 1) {
          Set8(1, 0);
        } else {
          Set16(1, 1);
        }
        if (use_signed) {
          codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);
          codegen_gen(sSEC, Implied, 0, 0);
          codegen_gen(sSBC, Immediate, z->a, 0);
        } else {
          codegen_gen(sCMP, Immediate, z->a, 0);
        }
    } else {
        // Compare y register with z register
        load(y);
        load(z);
        if ((y->type->size == 1) && (z->type->size == 1)) {
          Set8(1, 0);
        } else {
          Set16(1, 1);
        }
        if (use_signed) {
          codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);
          codegen_gen(sSEC, Implied, 0, 0);
          codegen_gen(sSBC, DirectPage, reg_addr(z->r), 0);
        } else {
          codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);
          codegen_gen(sCMP, DirectPage, reg_addr(z->r), 0);
        }
        RH--;
    }
	Set16(1, 0);

    // Generate conditional branch based on increment direction
    if (w->a > 0) {
        // Positive increment: branch if greater than limit (exit loop)
        emitBranch(GT, y->type, Fixup, 0);  // Forward branch, will be fixed up later
    } else if (w->a < 0) {
        // Negative increment: branch if less than limit (exit loop)
        emitBranch(LT, y->type, Fixup, 0);  // Forward branch, will be fixed up later
    } else {
        ORS_Mark("zero increment");
        emitBranch(MI, y->type, Fixup, 0);  // This shouldn't happen, but handle error case
    }
    
    *L = ORG_pc - 2;  // Save location of branch for later fixup (BRL offset field)
    
    // Store initial value in loop variable
    ORG_Store(x, y);
}

void ORG_For2(ORG_Item *x, ORG_Item *y, ORG_Item *w) {
    (void)y;
    // Increment/decrement loop variable by step amount
    load(x);

    // Add the increment value to the loop variable
    if (w->mode == ORB_Const) {
        // Add immediate constant to accumulator
        if (w->a > 0) {
            codegen_gen(sCLC, Implied, 0, 0);
            codegen_gen(sADC, Immediate, w->a, 0);
        } else {
            // For negative increment, use SBC (subtract)
            codegen_gen(sSEC, Implied, 0, 0);
            codegen_gen(sSBC, Immediate, -w->a, 0);
        }
    } else {
        // Add register value (less common case)
        load(w);
        codegen_gen(sCLC, Implied, 0, 0);
        codegen_gen(sADC, DirectPage, reg_addr(w->r), 0);
        RH--;
    }
    
    // Store the incremented value back to the loop variable
    // The value is already in the accumulator, just store it to x
    if (x->mode == ORB_Var) {
	  codegen_gen(sLDY, Immediate, x->a, 0);
	  codegen_gen(sSTA, DirectPageIndirectIndexedY, SB_DP, 0);
    } else {
        codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);
    }
    RH--;
}

// Case statement operations

void ORG_CaseLabel(ORG_Item *x, LONGINT val, LONGINT *chain) {
  // Re-load case variable, compare with val; if equal, BRL into hit chain
  load(x);
  Set16(1, 1);
  codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);
  codegen_gen(sCMP, Immediate, val, 0);
  RH--;
  codegen_gen(sBNE, ProgramCounterRelative, ORG_pc + 2 + 3, 0);  // skip BRL
  codegen_gen(sBRL, Fixup, *chain, 0);
  *chain = ORG_pc - 2;
}

void ORG_CaseRange(ORG_Item *x, LONGINT lo, LONGINT hi, LONGINT *chain) {
  // Re-load case variable, unsigned subtraction trick: (val - lo) < (hi - lo + 1)
  load(x);
  Set16(1, 1);
  codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);
  RH--;
  codegen_gen(sSEC, Implied, 0, 0);
  codegen_gen(sSBC, Immediate, lo, 0);
  codegen_gen(sCMP, Immediate, hi - lo + 1, 0);
  codegen_gen(sBCS, ProgramCounterRelative, ORG_pc + 2 + 3, 0);  // skip BRL if out of range
  codegen_gen(sBRL, Fixup, *chain, 0);
  *chain = ORG_pc - 2;
}

// Branch and jump operations
LONGINT ORG_Here(void) {
    return ORG_pc;
}

/*
  PROCEDURE FJump*(VAR L: LONGINT);
  BEGIN Put3(BC, 7, L); L := pc-1
  END FJump;
*/
void ORG_FJump(LONGINT *L) {
    // Generate unconditional forward jump
    emitBranch(AL, intType, Fixup, *L);  // Unconditional forward branch (condition 7 = always)
    *L = ORG_pc - 2;    // Save location for later fixup (BRL offset field)
}

/*
  PROCEDURE CFJump*(VAR x: Item);
  BEGIN
    IF x.mode # Cond THEN loadCond(x) END ;
    Put3(BC, negated(x.r), x.a); FixLink(x.b); x.a := pc-1
  END CFJump;
*/
void ORG_CFJump(ORG_Item *x) {
    if (x->mode != Cond) {
        loadCond(x);
    }
    
	emitBranch(negated(x->r), x->orig_type, Fixup, x->a);
	ORG_FixLink(x->b);  // Fix up TRUE branches
	x->a = ORG_pc - 2;  // Save location for FALSE branch fixup (BRL offset field)
}

void ORG_BJump(LONGINT L) {
  codegen_gen(sBRA, ProgramCounterRelative, L, 0);
}

void ORG_CBJump(ORG_Item *x, LONGINT L) {
    if (x->mode != Cond) {
        loadCond(x);
    }
    // Generate branch with negated condition (for backward jump on FALSE)
    emitBranch(negated(x->r), x->orig_type, ProgramCounterRelative, L);
    ORG_FixLink(x->b);     // Fix up TRUE branches
    FixLinkWith(x->a, L);  // Fix up FALSE branches to target L
}

void ORG_Fixup(ORG_Item *x) {
    ORG_FixLink(x->a);
}

static void SaveRegs(LONGINT r) {
    LONGINT ri = 0;
    // 65C816: Push registers to stack
	Set16(1, 1);
    frame += 2 * r;  // Each register is 2 bytes (16-bit)
    do {
        // LDA $reg and PHA to push register value onto stack
        codegen_gen(sLDA, DirectPage, reg_addr(ri), 0);  // LDA $reg
        codegen_gen(sPHA, Implied, 0, 0);                // PHA
        ri++;
    } while (ri < r);
}

static void RestoreRegs(LONGINT r) {
    LONGINT ri = r;
    // 65C816: Pull registers from stack in reverse order
	Set16(1, 1);
    do {
        ri--;
        // PLA and STA $reg to restore register value from stack
        codegen_gen(sPLA, Implied, 0, 0);                // PLA
        codegen_gen(sSTA, DirectPage, reg_addr(ri), 0);  // STA $reg
    } while (ri > 0);
    frame -= 2 * r;  // Each register is 2 bytes (16-bit)
}

void ORG_PrepCall(ORG_Item *x, LONGINT *r) {
    if (x->mode > ORB_Par) {
        load(x);
    }
    *r = RH;
    if (RH > 0) {
        SaveRegs(RH);
        RH = 0;
    }
    // 65C816: Stack allocation moved to ORG_Call to happen immediately before JSR
}

void ORG_Call(ORG_Item *x, LONGINT r) {
  Set16(1, 1); // Always in long mode when entering a procedure
  if (x->mode == ORB_Const) {
	if (x->r < 0) {
	  // 65C816: Imported procedure - encode mno in bank byte, exno in address
	  int mno = -(x->r);
	  int exno = x->a;
	  int encoded = (mno << 16) | (exno & 0xFFFF);
	  codegen_gen(sJSL, AbsoluteLong, encoded, 0);  // JSL mno:exno
	} else if (x->b == 1) {
	  // 65C816: Exported procedure called locally - use JSL (bank 0)
	  codegen_gen(sJSL, AbsoluteLong, x->a, 0);  // JSL procedure_address
	} else {
	  // 65C816: Local procedure - JSR to procedure address
	  codegen_gen(sJSR, Absolute, x->a, 0);  // JSR procedure_address
	}
    } else {
	  // Indirect call through procedure variable
	  // Uses RTL trampoline (DP-relative): PHK; PER; SEP; LDA bank; PHA;
	  // REP; LDA addr; DEC; PHA; RTL
	  // PER operand = 11 ($0B): 16 bytes from PHK to return point
	  int addr_reg, bank_reg;
	  if (x->mode <= ORB_Par) {
		// Proc var not yet loaded — load 4-byte address into 2 registers
		load(x);
		addr_reg = reg_addr(RH - 2);
		bank_reg = reg_addr(RH - 1);
		if (check) {
		  // NIL check: ORA addr and bank words, trap if zero
		  codegen_gen(sLDA, DirectPage, addr_reg, 0);
		  codegen_gen(sORA, DirectPage, bank_reg, 0);
		  Trap(NE, 5);  // NE = non-nil → skip BRK
		}
		codegen_gen(sPHK, Implied, 0, 0);
		codegen_gen(sPER, Immediate, 0x000B, 0);
		Set8(1, 0);
		codegen_gen(sLDA, DirectPage, bank_reg, 0);
		codegen_gen(sPHA, Implied, 0, 0);
		Set16(1, 0);
		codegen_gen(sLDA, DirectPage, addr_reg, 0);
		codegen_gen(sDEC, Accumulator, 0, 0);
		codegen_gen(sPHA, Implied, 0, 0);
		codegen_gen(sRTL, Implied, 0, 0);
		RH -= 2;  // free proc addr registers
	  } else {
		// Proc var was loaded in PrepCall and saved on stack by SaveRegs
		// Pop 4-byte proc address back from stack (pushed last = on top)
		codegen_gen(sPLA, Implied, 0, 0);                       // pull bank (pushed last)
		codegen_gen(sSTA, DirectPage, reg_addr(1), 0);
		codegen_gen(sPLA, Implied, 0, 0);                       // pull addr
		codegen_gen(sSTA, DirectPage, reg_addr(0), 0);
		addr_reg = reg_addr(0);
		bank_reg = reg_addr(1);
		r -= 2;
		frame -= 4;
		if (check) {
		  codegen_gen(sLDA, DirectPage, addr_reg, 0);
		  codegen_gen(sORA, DirectPage, bank_reg, 0);
		  Trap(NE, 5);
		}
		codegen_gen(sPHK, Implied, 0, 0);
		codegen_gen(sPER, Immediate, 0x000B, 0);
		Set8(1, 0);
		codegen_gen(sLDA, DirectPage, bank_reg, 0);
		codegen_gen(sPHA, Implied, 0, 0);
		Set16(1, 0);
		codegen_gen(sLDA, DirectPage, addr_reg, 0);
		codegen_gen(sDEC, Accumulator, 0, 0);
		codegen_gen(sPHA, Implied, 0, 0);
		codegen_gen(sRTL, Implied, 0, 0);
	  }
    }
    
    if (x->type->base->form == ORB_NoTyp) {
	  if (r > 0) RestoreRegs(r);
	  RH = r;
    } else {
	  int wide = (x->type->base->form == ORB_Pointer ||
	              x->type->base->form == ORB_Real ||
	              x->type->base->form == ORB_Proc);
	  if (r > 0) {
		// Move function result from R[0] to R[r] before restoring saved regs
		Set16(1, 1);
		codegen_gen(sLDA, DirectPage, reg_addr(0), 0);    // LDA R[0]
		codegen_gen(sSTA, DirectPage, reg_addr(r), 0);     // STA R[r]
		if (wide) {
		  codegen_gen(sLDA, DirectPage, reg_addr(1), 0);   // LDA R[1] (bank/high word)
		  codegen_gen(sSTA, DirectPage, reg_addr(r+1), 0); // STA R[r+1]
		}
		RestoreRegs(r);
	  }
	  x->mode = Reg;
	  x->r = r;
	  RH = wide ? r + 2 : r + 1;
    }
}

void ORG_Enter(ORB_Object *params, LONGINT frame_size, BOOLEAN expo, BOOLEAN int_proc) {
  LONGINT r;
  ORB_Object *param;

  if (!int_proc) {
	if (frame_size >= 0x4000) {
	  ORS_Mark("too many locals");
	}

	Set16(1, 1);
	if (expo) {
	  // Save caller's SB and bank, load own module's SB and bank
	  codegen_gen(sLDA, DirectPage, SB_DP, 0);   // LDA SB
	  codegen_gen(sPHA, Implied, 0, 0);                  // PHA (save SB on stack)
	  codegen_gen(sLDA, DirectPage, BANK_DP, 0);  // LDA bank
	  codegen_gen(sPHA, Implied, 0, 0);                  // PHA (save bank on stack)
	  reloc[relocC++] = ORG_pc;                          // record for relocation
	  codegen_gen(sLDA, Immediate, 0x0000, 0);           // LDA #var_base (patched)
	  codegen_gen(sSTA, DirectPage, SB_DP, 0);    // STA SB
	  reloc[relocC++] = ORG_pc | 0x80000000;                 // bank reloc flag
	  codegen_gen(sLDA, Immediate, 0x0000, 0);           // LDA #bank (patched)
	  codegen_gen(sSTA, DirectPage, BANK_DP, 0);  // STA bank
	}

	if (frame_size > 0) {
	  // Allocate stack space for parameters and locals
	  codegen_gen(sTSC, Implied, 0, 0);                        // TSC (Transfer Stack to A)
	  codegen_gen(sSEC, Implied, 0, 0);                        // SEC
	  codegen_gen(sSBC, Immediate, frame_size, 0);       // SBC #total_frame_size
	  codegen_gen(sTCS, Implied, 0, 0);                        // TCS (Transfer A to Stack)
	}

	r = 0;
        
	// 65C816: Store register parameters to their stack locations using actual parameter types
	r = 0;  // Start with register 0
	param = params;  // Start with first parameter

	Set16(1, 1);
	while (param != NULL && (param->class == ORB_Var || param->class == ORB_Par)) {
	  // For VAR parameters (ORB_Par with rdo=FALSE), we need to store the pointer value itself
	  // to the stack frame, not store through the pointer
	  if (param->class == ORB_Par && param->type->form == ORB_Array && param->type->len < 0) {
	    // Open array parameter (VAR or value): Store both array address and length
	    // First register contains array address, second register contains array length
	    
	    // Store the array address from first two registers  
	    codegen_gen(sLDA, DirectPage, reg_addr(r + 0), 0);     // LDA $reg (load address low)
	    codegen_gen(sSTA, StackRelative, param->val, 0);       // STA param->val,S (store address low)
	    codegen_gen(sLDA, DirectPage, reg_addr(r + 1), 0);     // LDA $reg+1 (load address high)  
	    codegen_gen(sSTA, StackRelative, param->val + 2, 0);   // STA param->val+1,S (store address high)
	    
	    // Store the array length from third register  
	    codegen_gen(sLDA, DirectPage, reg_addr(r + 2), 0);     // LDA $reg+2 (load array length)
	    codegen_gen(sSTA, StackRelative, param->val + 4, 0);   // STA param->val+4,S (store length)
	    
	    // Result on stack: [addr_low] [addr_high] [data_bank] [padding] [len_low] [len_high] = 6-byte VAR open array
	  } else if (param->class == ORB_Par && param->type->form == ORB_Record) {
	    // VAR record parameter: Store 8-byte value (addr + bank + tag_lo + tag_hi)
	    codegen_gen(sLDA, DirectPage, reg_addr(r + 0), 0);     // LDA $reg (address)
	    codegen_gen(sSTA, StackRelative, param->val, 0);       // STA param->val,S
	    codegen_gen(sLDA, DirectPage, reg_addr(r + 1), 0);     // LDA $reg+1 (bank)
	    codegen_gen(sSTA, StackRelative, param->val + 2, 0);   // STA param->val+2,S
	    codegen_gen(sLDA, DirectPage, reg_addr(r + 2), 0);     // LDA $reg+2 (tag_lo)
	    codegen_gen(sSTA, StackRelative, param->val + 4, 0);   // STA param->val+4,S
	    codegen_gen(sLDA, DirectPage, reg_addr(r + 3), 0);     // LDA $reg+3 (tag_hi)
	    codegen_gen(sSTA, StackRelative, param->val + 6, 0);   // STA param->val+6,S
	  } else if (param->class == ORB_Par) {
	    // VAR parameter or promoted value param: Store 4-byte pointer value to stack using two registers
	    // First register contains 16-bit address, second register contains data bank (0)

	    // Store the 16-bit address from first register
	    codegen_gen(sLDA, DirectPage, reg_addr(r + 0), 0);     // LDA $reg (load 16-bit address)
	    codegen_gen(sSTA, StackRelative, param->val, 0);       // STA param->val,S (store address)

	    // Store the data bank and high byte from second register
	    codegen_gen(sLDA, DirectPage, reg_addr(r + 1), 0);     // LDA $reg+1 (load data bank)
	    codegen_gen(sSTA, StackRelative, param->val + 2, 0);   // STA param->val+2,S (store data bank)

	    // Result on stack: [addr_low] [addr_high] [data_bank] [padding] = 4-byte pointer
	  } else if (param->type->form == ORB_Real || param->type->form == ORB_Proc) {
	    // REAL or Proc value parameter: store 4 bytes (low word + high word) directly
	    codegen_gen(sLDA, DirectPage, reg_addr(r), 0);          // LDA low word
	    codegen_gen(sSTA, StackRelative, param->val, 0);        // STA param_offset,S
	    codegen_gen(sLDA, DirectPage, reg_addr(r + 1), 0);      // LDA high word
	    codegen_gen(sSTA, StackRelative, param->val + 2, 0);    // STA param_offset+2,S
	  } else {
	    // Regular parameter or complex type parameter: Use normal ORG_Store
	    ORG_Item param_item, reg_item;

	    // Use ORG_MakeItem to create parameter item (destination) from ORB_Object
	    ORG_MakeItem(&param_item, param, param->lev);

	    // Set up register item (source)
	    reg_item.mode = Reg;
	    reg_item.type = param->type;
	    reg_item.r = r;             // Register number
	    reg_item.rdo = TRUE;

	    // Use ORG_Store to handle the transfer with correct processor modes
	    ORG_Store(&param_item, &reg_item);
	  }
	  
	  // Advance register pointer based on parameter type
	  // Check open array VAR first, then VAR record, then simple VAR, then regular
	  if (param->class == ORB_Par && param->type->form == ORB_Array && param->type->len < 0) {
	    r += 3;  // Open array parameter uses three registers (addr_low + addr_high + length)
	  } else if (param->class == ORB_Par && param->type->form == ORB_Record) {
	    r += 4;  // VAR record parameter uses four registers (addr + bank + tag_lo + tag_hi)
	  } else if (param->class == ORB_Par) {
	    r += 2;  // VAR or promoted value parameter uses two registers (address + data bank)
	  } else {
	    if (param->type->size <= 2) {
	      r++;     // INTEGER/BYTE/CHAR/BOOLEAN: one register
	    } else {
	      r += 2;  // REAL: two registers
	    }
	  }
	  param = param->next;
	}
	
	// Reset register stack - parameters are now stored on stack, registers are free
	RH = 0;
  } else {
	// Interrupt procedure - allocate full stack frame
	if (frame_size > 0) {
	  codegen_gen(sSEC, Implied, 0, 0);           // SEC
	  codegen_gen(sSBC, Immediate, frame_size, 0); // SBC #locblksize
	  codegen_gen(sTCS, Implied, 0, 0);           // TCS (Transfer A to Stack)
	}
  }
}

void ORG_Return(INTEGER form, ORG_Item *x, LONGINT size, BOOLEAN expo, BOOLEAN int_proc) {
  if (form != ORB_NoTyp) {
	load(x);
  }
  
  if (!int_proc) {
	Set16(1, 1);
	// 65C816: Simple stack frame deallocation 
	if (size > 0) {
	  codegen_gen(sTSC, Implied, 0, 0);           // TSC (Transfer Stack to A)
	  codegen_gen(sCLC, Implied, 0, 0);           // CLC
	  codegen_gen(sADC, Immediate, size, 0);     // ADC #size (deallocate frame)
	  codegen_gen(sTCS, Implied, 0, 0);           // TCS (Transfer A to Stack)
	}
	if (expo) {
	  // Restore caller's bank and SB before returning (reverse push order)
	  codegen_gen(sPLA, Implied, 0, 0);                  // PLA (bank)
	  codegen_gen(sSTA, DirectPage, BANK_DP, 0);  // STA bank
	  codegen_gen(sPLA, Implied, 0, 0);                  // PLA (SB)
	  codegen_gen(sSTA, DirectPage, SB_DP, 0);    // STA SB
	  codegen_gen(sRTL, Implied, 0, 0);                  // RTL
	} else {
	  codegen_gen(sRTS, Implied, 0, 0);                  // RTS
	}
  } else {
	// Interrupt procedure - deallocate full stack frame
	if (size > 0) {
	  codegen_gen(sCLC, Implied, 0, 0);           // CLC
	  codegen_gen(sADC, Immediate, size, 0);     // ADC #size
	  codegen_gen(sTCS, Implied, 0, 0);           // TCS (Transfer A to Stack)
	}
	codegen_gen(sRTI, Implied, 0, 0);  // RTI
  }
  RH = 0;
}

// Inline procedures
void ORG_Increment(LONGINT upordown, ORG_Item *x, ORG_Item *y) {
    // Follow the RISC implementation exactly but adapt to 65C816
    BOOLEAN is_byte = (x->type == byteType);
    BOOLEAN is_increment = (upordown == 0);
    LONGINT zr;
    
    // Default y to 1 if no type specified
    if (y->type->form == ORB_NoTyp) {
        y->mode = ORB_Const;
        y->a = 1;
    }
    
    // Check if we can optimize to INC/DEC (increment/decrement by 1)
    BOOLEAN can_use_inc_dec = (y->mode == ORB_Const) && (y->a == 1);
    
    if ((x->mode == ORB_Var) && (x->r > 0)) {
        // Local variable case: RISC: zr := RH; Put2(Ldr+v, zr, SP, x->a); incR;
        zr = RH;
        if (is_byte) Set8(1, 0); else Set16(1, 1);
        
        // Load from stack to register: LDA x,S -> STA $zr
        codegen_gen(sLDA, StackRelative, x->a + frame, 0);
        codegen_gen(sSTA, DirectPage, reg_addr(zr), 0);
        incR();
        
        // Perform operation
        if (y->mode == ORB_Const) {
            if (can_use_inc_dec) {
                // Use INC/DEC instructions
                codegen_gen(sLDA, DirectPage, reg_addr(zr), 0);
                if (is_increment) {
                    codegen_gen(sINC, Accumulator, 0, 0);
                } else {
                    codegen_gen(sDEC, Accumulator, 0, 0);
                }
                codegen_gen(sSTA, DirectPage, reg_addr(zr), 0);
            } else {
                // Use ADC/SBC instructions
                codegen_gen(sLDA, DirectPage, reg_addr(zr), 0);
                if (is_increment) {
                    codegen_gen(sCLC, Implied, 0, 0);
                    codegen_gen(sADC, Immediate, y->a, 0);
                } else {
                    codegen_gen(sSEC, Implied, 0, 0);
                    codegen_gen(sSBC, Immediate, y->a, 0);
                }
                codegen_gen(sSTA, DirectPage, reg_addr(zr), 0);
            }
        } else {
            load(y);
            codegen_gen(sLDA, DirectPage, reg_addr(zr), 0);
            if (is_increment) {
                codegen_gen(sCLC, Implied, 0, 0);
                codegen_gen(sADC, DirectPage, reg_addr(y->r), 0);
            } else {
                codegen_gen(sSEC, Implied, 0, 0);
                codegen_gen(sSBC, DirectPage, reg_addr(y->r), 0);
            }
            codegen_gen(sSTA, DirectPage, reg_addr(zr), 0);
            RH--;
        }

        // Store back to stack: RISC: Put2(Str+v, zr, SP, x->a);
        codegen_gen(sLDA, DirectPage, reg_addr(zr), 0);
        codegen_gen(sSTA, StackRelative, x->a + frame, 0);
        
        if (is_byte) Set16(1, 1);  // Restore 16-bit mode
        RH--;  // RISC: DEC(RH)
        
    } else {
        // Global variable case: RISC: loadAdr(x); zr := RH; Put2(Ldr+v, RH, x->r, 0); incR;
        loadAdr(x);    // After this: RH=2, x->r=0 (address in registers 0,1)
        zr = RH;       // zr = 2 (next available register)
        if (is_byte) Set8(1, 0); else Set16(1, 1);
        
        // Load value from address into register zr
        codegen_gen(sLDX, DirectPage, reg_addr(x->r), 0);      // LDX $address_low (reg 0)
        codegen_gen(sLDA, AbsoluteIndexedX, 0, 0);             // LDA $0000,X
        codegen_gen(sSTA, DirectPage, reg_addr(zr), 0);        // STA $zr (reg 2)
        incR();        // RH = 3
        
        // Perform operation on register zr
        if (y->mode == ORB_Const) {
            // RISC: Put1a(op, zr, zr, y->a);
            if (can_use_inc_dec) {
                // Use INC/DEC instructions  
                codegen_gen(sLDA, DirectPage, reg_addr(zr), 0);
                if (is_increment) {
                    codegen_gen(sINC, Accumulator, 0, 0);
                } else {
                    codegen_gen(sDEC, Accumulator, 0, 0);
                }
                codegen_gen(sSTA, DirectPage, reg_addr(zr), 0);
            } else {
                // Use ADC/SBC instructions
                codegen_gen(sLDA, DirectPage, reg_addr(zr), 0);
                if (is_increment) {
                    codegen_gen(sCLC, Implied, 0, 0);
                    codegen_gen(sADC, Immediate, y->a, 0);
                } else {
                    codegen_gen(sSEC, Implied, 0, 0);
                    codegen_gen(sSBC, Immediate, y->a, 0);
                }
                codegen_gen(sSTA, DirectPage, reg_addr(zr), 0);
            }
        } else {
            load(y);
            // RISC: Put0(op, zr, zr, y->r);
            codegen_gen(sLDA, DirectPage, reg_addr(zr), 0);
            if (is_increment) {
                codegen_gen(sCLC, Implied, 0, 0);
                codegen_gen(sADC, DirectPage, reg_addr(y->r), 0);
            } else {
                codegen_gen(sSEC, Implied, 0, 0);
                codegen_gen(sSBC, DirectPage, reg_addr(y->r), 0);
            }
            codegen_gen(sSTA, DirectPage, reg_addr(zr), 0);
            RH--;
        }
        
        // Store back to address: RISC: Put2(Str+v, zr, x->r, 0);
        codegen_gen(sLDX, DirectPage, reg_addr(x->r), 0);      // LDX $address_low (reg 0)  
        codegen_gen(sLDA, DirectPage, reg_addr(zr), 0);        // LDA $zr (reg 2)
        codegen_gen(sSTA, AbsoluteIndexedX, 0, 0);             // STA $0000,X
        
        if (is_byte) Set16(1, 1);  // Restore 16-bit mode
        
        // Clean up registers: RISC: DEC(RH, 2)
        // We had: loadAdr incremented RH by 2 (0->2), then we incremented by 1 (2->3)
        // So we need to decrement by 3 to get back to 0
        RH -= 3;
    }
}

void ORG_Include(LONGINT inorex, ORG_Item *x, ORG_Item *y) {
    // INCL(x, y): x := x + {y}  (set bit y in x)
    // EXCL(x, y): x := x - {y}  (clear bit y in x)
    ORG_Item orig = *x;

    if (x->mode == ORB_Var && x->r > 0) {
        // Local variable: load from stack, modify, store back
        Set16(1, 1);
        LONGINT zr = RH;
        codegen_gen(sLDA, StackRelative, x->a + frame, 0);   // Load set value from stack
        codegen_gen(sSTA, DirectPage, reg_addr(zr), 0);
        incR();

        if (y->mode == ORB_Const) {
            LONGINT mask = (1L << y->a) & 0xFFFF;
            codegen_gen(sLDA, DirectPage, reg_addr(zr), 0);
            if (inorex == 0) {
                // INCL: OR with mask
                codegen_gen(sORA, Immediate, (int)mask, 0);
            } else {
                // EXCL: AND with NOT mask
                codegen_gen(sAND, Immediate, (int)(~mask & 0xFFFF), 0);
            }
            codegen_gen(sSTA, DirectPage, reg_addr(zr), 0);
        } else {
            load(y);
            // Build mask: 1 << y
            codegen_gen(sLDA, Immediate, 1, 0);
            codegen_gen(sLDX, DirectPage, reg_addr(y->r), 0);
            LONGINT skip = ORG_pc + 2 + 4;
            codegen_gen(sBEQ, ProgramCounterRelative, skip, 0);
            LONGINT loop_top = ORG_pc;
            codegen_gen(sASL, Accumulator, 0, 0);
            codegen_gen(sDEX, Implied, 0, 0);
            codegen_gen(sBNE, ProgramCounterRelative, loop_top, 0);
            // skip: A = mask
            if (inorex == 0) {
                // INCL: OR mask into set
                codegen_gen(sORA, DirectPage, reg_addr(zr), 0);
            } else {
                // EXCL: AND NOT mask into set
                codegen_gen(sEOR, Immediate, 0xFFFF, 0);
                codegen_gen(sAND, DirectPage, reg_addr(zr), 0);
            }
            codegen_gen(sSTA, DirectPage, reg_addr(zr), 0);
            RH--;
        }

        // Store back to stack
        codegen_gen(sLDA, DirectPage, reg_addr(zr), 0);
        codegen_gen(sSTA, StackRelative, orig.a + frame, 0);
        RH--;

    } else {
        // Global variable: loadAdr, load value, modify, store back
        loadAdr(x);    // RH += 2 (address in regs)
        LONGINT zr = RH;
        Set16(1, 1);

        // Load value from address
        codegen_gen(sLDX, DirectPage, reg_addr(x->r), 0);
        codegen_gen(sLDA, AbsoluteIndexedX, 0, 0);
        codegen_gen(sSTA, DirectPage, reg_addr(zr), 0);
        incR();

        if (y->mode == ORB_Const) {
            LONGINT mask = (1L << y->a) & 0xFFFF;
            codegen_gen(sLDA, DirectPage, reg_addr(zr), 0);
            if (inorex == 0) {
                codegen_gen(sORA, Immediate, (int)mask, 0);
            } else {
                codegen_gen(sAND, Immediate, (int)(~mask & 0xFFFF), 0);
            }
            codegen_gen(sSTA, DirectPage, reg_addr(zr), 0);
        } else {
            load(y);
            // Build mask: 1 << y
            codegen_gen(sLDA, Immediate, 1, 0);
            codegen_gen(sLDX, DirectPage, reg_addr(y->r), 0);
            LONGINT skip = ORG_pc + 2 + 4;
            codegen_gen(sBEQ, ProgramCounterRelative, skip, 0);
            LONGINT loop_top = ORG_pc;
            codegen_gen(sASL, Accumulator, 0, 0);
            codegen_gen(sDEX, Implied, 0, 0);
            codegen_gen(sBNE, ProgramCounterRelative, loop_top, 0);
            // skip: A = mask
            if (inorex == 0) {
                codegen_gen(sORA, DirectPage, reg_addr(zr), 0);
            } else {
                codegen_gen(sEOR, Immediate, 0xFFFF, 0);
                codegen_gen(sAND, DirectPage, reg_addr(zr), 0);
            }
            codegen_gen(sSTA, DirectPage, reg_addr(zr), 0);
            RH--;
        }

        // Store back to address
        codegen_gen(sLDX, DirectPage, reg_addr(x->r), 0);
        codegen_gen(sLDA, DirectPage, reg_addr(zr), 0);
        codegen_gen(sSTA, AbsoluteIndexedX, 0, 0);
        RH -= 3;
    }
}

void ORG_Assert(ORG_Item *x) {
  LONGINT cond;
  
  if (x->mode != Cond) {
	loadCond(x);
  }
  
  if (x->a == 0) {
	cond = negated(x->r);
  } else {
    // RISC: Put3(BC, x->r, x->b);
	ORG_FixLink(x->a);
	x->b = ORG_pc - 1;
	cond = 7;
  }
  Trap(cond, 7);
  ORG_FixLink(x->b);
}

void ORG_New(ORG_Item *x) {
  // 65C816: Heap allocation via BRK #10 trap
  // Emulator returns: addr in A, bank in X
  // Heap layout: [tag_lo:2][tag_hi:2][object data...] — pointer points to data
  ORB_Type *baseType = x->type->base;
  ORG_Item y = *x;  // save destination
  ORG_Item z;
  Set16(1, 1);

  // Compute absolute 4-byte tag: SB + T->len
  int sb = GetSB(-baseType->mno);
  codegen_gen(sLDA, DirectPage, sb, 0);
  codegen_gen(sCLC, Implied, 0, 0);
  codegen_gen(sADC, Immediate, baseType->len, 0);
  codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);      // tag_lo
  codegen_gen(sSTZ, DirectPage, reg_addr(RH + 1), 0);  // tag_hi = 0
  incR(); incR();  // 2 regs for tag

  // Allocate size + 4
  codegen_gen(sLDA, Immediate, baseType->size + 4, 0);
  codegen_gen(sBRK, Immediate, 10, 0);
  codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);      // heap base addr
  codegen_gen(sSTX, DirectPage, reg_addr(RH + 1), 0);  // bank

  // Store 4-byte tag at heap base
  codegen_gen(sLDA, DirectPage, reg_addr(RH - 2), 0);            // tag_lo
  codegen_gen(sSTA, DirectPageIndirectLong, reg_addr(RH), 0);    // [base] := tag_lo
  codegen_gen(sLDY, Immediate, 2, 0);
  codegen_gen(sLDA, DirectPage, reg_addr(RH - 1), 0);            // tag_hi
  codegen_gen(sSTA, DirectPageIndirectLongIndexedY, reg_addr(RH), 0);  // [base+2] := tag_hi

  // Adjust pointer: addr += 4 (skip past tag)
  codegen_gen(sCLC, Implied, 0, 0);
  codegen_gen(sLDA, DirectPage, reg_addr(RH), 0);
  codegen_gen(sADC, Immediate, 4, 0);
  codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);

  // Store pointer to destination variable
  z.r = RH;
  z.mode = Reg;
  z.type = y.type;
  incR(); incR();  // allocate pointer pair
  ORG_Store(&y, &z);  // store 4-byte pointer to variable (frees the 2 regs)
  RH -= 2;  // free tag pair
}

void ORG_Pack(ORG_Item *x, ORG_Item *y) {
  ORG_Item z = *x;
  load(x);
  load(y);
  // RISC: Put1(Lsl, y->r, y->r, 23);
  // RISC: Put0(Add, x->r, x->r, y->r);
  RH--;
  ORG_Store(&z, x);
}

void ORG_Unpk(ORG_Item *x, ORG_Item *y) {
  ORG_Item z, e0;
  z = *x;
  load(x);
  e0.mode = Reg;
  e0.r = RH;
  e0.type = intType;
  // RISC: Put1(Asr, RH, x->r, 23);
  // RISC: Put1(Sub, RH, RH, 127);
  ORG_Store(y, &e0);
  incR();
  // RISC: Put1(Lsl, RH, RH, 23);
  // RISC: Put0(Sub, x->r, x->r, RH);
  ORG_Store(&z, x);
}

void ORG_IntEn(ORG_Item *x) {
  (void)x;
}

void ORG_Get(ORG_Item *bank, ORG_Item *addr, ORG_Item *var) {
  // 65C816: GET(bank, address, var) - load value from [bank:address] into variable
  load(addr);
  load(bank);  // bank in R[RH-1], address in R[RH-2]
  addr->type = var->type;
  addr->mode = RegI;
  addr->a = 0;
  ORG_Store(var, addr);
}

void ORG_Put(ORG_Item *bank, ORG_Item *addr, ORG_Item *val) {
  // 65C816: PUT(bank, address, value) - store value at [bank:address]
  load(addr);
  load(bank);  // bank in R[RH-1], address in R[RH-2]
  addr->type = val->type;
  addr->mode = RegI;
  addr->a = 0;
  ORG_Store(addr, val);
}

void ORG_Copy(ORG_Item *x, ORG_Item *y, ORG_Item *z) {
  load(x);
  load(y);

  if (z->mode == ORB_Const) {
    if (z->a > 0) {
      load(z);
    } else {
      ORS_Mark("bad count");
    }
  } else {
    load(z);
    if (check) {
      Trap(LT, 3);
    }
  }

  // 65C816: word-by-word copy loop using Y as byte offset
  Set16(1, 1);
  codegen_gen(sLDY, Immediate, 0, 0);
  LONGINT loop_top = ORG_pc;
  codegen_gen(sLDA, DirectPageIndirectIndexedY, reg_addr(x->r), 0); // LDA (src),Y
  codegen_gen(sSTA, DirectPageIndirectIndexedY, reg_addr(y->r), 0); // STA (dst),Y
  codegen_gen(sINY, Implied, 0, 0);
  codegen_gen(sINY, Implied, 0, 0);  // Y += 2
  codegen_gen(sLDA, DirectPage, reg_addr(z->r), 0);  // load count
  codegen_gen(sDEC, Accumulator, 0, 0);               // count--
  codegen_gen(sSTA, DirectPage, reg_addr(z->r), 0);   // save count
  codegen_gen(sBNE, ProgramCounterRelative, loop_top, 0);
  RH -= 3;
}

void ORG_TRB(ORG_Item *x, ORG_Item *y) {
  // 65C816: TRB(addr, mask) - Test and Reset Bits at address
  // Semantics: mem[addr] := mem[addr] AND NOT(mask)
  if (x->mode == ORB_Const) {
    load(y);
    Set16(1, 1);
    codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);
    codegen_gen(sTRB, Absolute, x->a, 0);
    RH--;
  } else {
    load(x);
    load(y);
    Set16(1, 1);
    // A = ~mask AND mem[addr]
    codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);         // A = mask
    codegen_gen(sEOR, Immediate, 0xFFFF, 0);                  // A = ~mask
    codegen_gen(sAND, DirectPageIndirect, reg_addr(x->r), 0); // A = ~mask AND mem[addr]
    codegen_gen(sSTA, DirectPageIndirect, reg_addr(x->r), 0); // mem[addr] = result
    RH -= 2;
  }
}

void ORG_TSB(ORG_Item *x, ORG_Item *y) {
  // 65C816: TSB(addr, mask) - Test and Set Bits at address
  // Semantics: mem[addr] := mem[addr] OR mask
  if (x->mode == ORB_Const) {
    load(y);
    Set16(1, 1);
    codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);
    codegen_gen(sTSB, Absolute, x->a, 0);
    RH--;
  } else {
    load(x);
    load(y);
    Set16(1, 1);
    // A = mask OR mem[addr]
    codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);         // A = mask
    codegen_gen(sORA, DirectPageIndirect, reg_addr(x->r), 0); // A = mask OR mem[addr]
    codegen_gen(sSTA, DirectPageIndirect, reg_addr(x->r), 0); // mem[addr] = result
    RH -= 2;
  }
}

void ORG_Exec(ORG_Item *addr, ORG_Item *bank) {
  // SYSTEM.EXEC(addr, bank) — indirect JSL to module entry point
  // Uses RTL trampoline: PHK; PER; SEP; LDA bank; PHA; REP; LDA addr; DEC; PHA; RTL
  // PER operand = $0B: 16 bytes from PHK to return point
  load(addr);
  load(bank);
  int addr_reg = reg_addr(addr->r);
  int bank_reg = reg_addr(bank->r);
  // Save caller's SB and BANK_DP (called module's init will overwrite them)
  codegen_gen(sLDA, DirectPage, SB_DP, 0);       // LDA SB
  codegen_gen(sPHA, Implied, 0, 0);               // PHA
  codegen_gen(sLDA, DirectPage, BANK_DP, 0);      // LDA BANK_DP
  codegen_gen(sPHA, Implied, 0, 0);               // PHA
  // Indirect JSL via RTL trampoline
  codegen_gen(sPHK, Implied, 0, 0);               // PHK (push return bank)
  codegen_gen(sPER, Immediate, 0x000B, 0);        // PER +11 (push return addr)
  Set8(1, 0);                                     // SEP #$20
  codegen_gen(sLDA, DirectPage, bank_reg, 0);     // LDA bank (8-bit)
  codegen_gen(sPHA, Implied, 0, 0);               // PHA (target bank)
  Set16(1, 0);                                    // REP #$20
  codegen_gen(sLDA, DirectPage, addr_reg, 0);     // LDA addr
  codegen_gen(sDEC, Accumulator, 0, 0);           // DEC (RTL adds 1)
  codegen_gen(sPHA, Implied, 0, 0);               // PHA (target addr)
  codegen_gen(sRTL, Implied, 0, 0);               // RTL → jumps to target
  // Return point: restore caller's BANK_DP and SB
  codegen_gen(sPLA, Implied, 0, 0);               // PLA
  codegen_gen(sSTA, DirectPage, BANK_DP, 0);      // STA BANK_DP
  codegen_gen(sPLA, Implied, 0, 0);               // PLA
  codegen_gen(sSTA, DirectPage, SB_DP, 0);        // STA SB
  RH -= 2;
}

// Inline functions
void ORG_Abs(ORG_Item *x) {
  if (x->mode == ORB_Const) {
	x->a = (x->a < 0) ? -x->a : x->a;  // ABS equivalent
  } else {
	load(x);
	if (x->type->form == ORB_Real) {
	  // Clear sign bit (bit 15 of high word)
	  Set16(1, 1);
	  codegen_gen(sLDA, DirectPage, reg_addr(x->r + 1), 0);
	  codegen_gen(sAND, Immediate, 0x7FFF, 0);
	  codegen_gen(sSTA, DirectPage, reg_addr(x->r + 1), 0);
	} else {
	  // if A < 0 then A = -A (two's complement negate)
	  Set16(1, 1);
	  codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);
	  codegen_gen(sBPL, ProgramCounterRelative, ORG_pc + 2 + 6, 0); // skip 6 bytes (EOR:3+INC:1+STA:2)
	  codegen_gen(sEOR, Immediate, 0xFFFF, 0);  // 3 bytes
	  codegen_gen(sINC, Accumulator, 0, 0);      // 1 byte
	  codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0); // 2 bytes (but skip also covers STA)
	  // skip lands here
	}
  }
}

void ORG_Odd(ORG_Item *x) {
  load(x);
  Set16(1, 1);
  codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);
  codegen_gen(sAND, Immediate, 1, 0);
  codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);
  SetCC(x, NE);
  RH--;
}

void ORG_Floor(ORG_Item *x) {
  load(x);
  // FLOOR: REAL (2 regs) -> INTEGER (1 reg)
  Set16(1, 1);
  // Copy R[x->r], R[x->r+1] to FP_A_LO, FP_A_HI
  codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);
  codegen_gen(sSTA, DirectPage, FP_A_LO, 0);
  codegen_gen(sLDA, DirectPage, reg_addr(x->r + 1), 0);
  codegen_gen(sSTA, DirectPage, FP_A_HI, 0);
  // JSR fp_floor (placeholder, fixup later)
  if (fp_fixup_count[FP_FLOOR] < maxFPFixups)
    fp_fixups[FP_FLOOR][fp_fixup_count[FP_FLOOR]++] = ORG_pc + 1;
  codegen_gen(sJSR, Absolute, 0x0000, 0);
  // Copy result from FP_A_LO back to R[x->r]
  codegen_gen(sLDA, DirectPage, FP_A_LO, 0);
  codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);
  RH--;  // free high word register
  x->type = intType;
}

void ORG_Float(ORG_Item *x) {
  load(x);
  // FLT: INTEGER (1 reg) -> REAL (2 regs)
  Set16(1, 1);
  // Copy R[x->r] to FP_A_LO; clear FP_A_HI
  codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);
  codegen_gen(sSTA, DirectPage, FP_A_LO, 0);
  codegen_gen(sSTZ, DirectPage, FP_A_HI, 0);
  // JSR fp_flt (placeholder, fixup later)
  if (fp_fixup_count[FP_FLT] < maxFPFixups)
    fp_fixups[FP_FLT][fp_fixup_count[FP_FLT]++] = ORG_pc + 1;
  codegen_gen(sJSR, Absolute, 0x0000, 0);
  // Copy FP_A_LO, FP_A_HI back to R[x->r], R[x->r+1]
  codegen_gen(sLDA, DirectPage, FP_A_LO, 0);
  codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);
  codegen_gen(sLDA, DirectPage, FP_A_HI, 0);
  incR();  // allocate high word register
  codegen_gen(sSTA, DirectPage, reg_addr(x->r + 1), 0);
  x->type = realType;
}

void ORG_Ord(ORG_Item *x) {
  if ((x->mode == ORB_Var) || (x->mode == ORB_Par) || 
	  (x->mode == RegI) || (x->mode == Cond)) {
	load(x);
  }
}

/*
    IF x.type.len >= 0 THEN
      IF x.mode = RegI THEN DEC(RH) END ;
      x.mode := ORB.Const; x.a := x.type.len
    ELSE (*open array*) Put2(Ldr, RH, SP, x.a + 4 + frame); x.mode := Reg; x.r := RH; incR
 */

void ORG_Len(ORG_Item *x) {
  if (x->type->len >= 0) {
	if (x->mode == RegI) {
	  RH--;
	}
	x->mode = ORB_Const;
	x->a = x->type->len;
  } else { // Open array (must be local)
	// For 65C816: Length is always at parameter base + 4
	// For first parameter: x->a=3, so length is at 3+4=7
	Set16(1, 1);
	codegen_gen(sLDA, StackRelative, x->a + 4 + frame, 0);  // LDA length,S
	codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);         // STA $reg (store length to register)
	x->mode = Reg;
	x->r = RH;
	incR();
  }
}

void ORG_Shift(LONGINT fct, ORG_Item *x, ORG_Item *y) {
  LONGINT op = sAND;
  
  load(x);
  switch (fct) {
  case 0: op = sASL; break;
  case 1: op = sLSR; break;
  case 2: op = sROL; break;
  }
  
  if (y->mode == ORB_Const) {
	if (y->a == 1) {
	  codegen_gen(op, DirectPage, reg_addr(x->r), 0);
	} else {
	  codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);
	  for (int i = 0; i < y->a; i++) {
		codegen_gen(op, Implied, 0, 0);
	  }
	  codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);
	}
  } else {
	// Not implement yet
	ORS_Mark("non-const shift not implemented");
	//load(y);
	//codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);
	//codegen_gen(op, DirectPage, reg_addr(x->r), 0);
	//codegen_gen(sSTA, DirectPage, reg_addr(RH-2), 0); 
	//RH--;
	//x->r = RH - 1;
  }
}

void ORG_Bitwise(LONGINT fct, ORG_Item *x, ORG_Item *y) {
  LONGINT op = sAND;

  load(x);
  switch (fct) {
  case 0: op = sAND; break;
  case 1: op = sEOR; break;
  case 2: op = sORA; break;
  }
  
  if (y->mode == ORB_Const) {
	codegen_gen(sLDA, Immediate, y->a & 0xffff, 0);
	codegen_gen(op, DirectPage, reg_addr(x->r), 0);
	codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0); 
  } else {
	load(y);
	codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);
	codegen_gen(op, DirectPage, reg_addr(x->r), 0);
	codegen_gen(sSTA, DirectPage, reg_addr(RH-2), 0); 
	RH--;
	x->r = RH - 1;
  }
}

void ORG_UML(ORG_Item *x, ORG_Item *y) {
  load(x);
  load(y);
  // RISC: Put0(Mul + 0x2000, x->r, x->r, y->r);
  RH--;
}

void ORG_Bit(ORG_Item *x, ORG_Item *y) {
  // 65C816: BIT(addr, n) - test if bit n at memory address addr is set
  // First load address into register, then read word through pointer
  load(x);
  // Allocate and zero bank register for RegI (long indirect needs 2 regs)
  codegen_gen(sSTZ, DirectPage, reg_addr(RH), 0);
  incR();
  x->mode = RegI;
  x->a = 0;
  x->type = intType;
  load(x);  // x->r now has the word at the address (frees bank reg)

  Set16(1, 1);
  if (y->mode == ORB_Const) {
    // Constant bit number: AND with compile-time mask
    codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);
    codegen_gen(sAND, Immediate, 1 << y->a, 0);
    codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);
    RH--;
  } else {
    load(y);
    // Variable bit number: build mask (1 << y) via shift loop
    codegen_gen(sLDA, Immediate, 1, 0);
    codegen_gen(sLDX, DirectPage, reg_addr(y->r), 0);
    codegen_gen(sBEQ, ProgramCounterRelative, ORG_pc + 2 + 4, 0); // skip loop if 0
    LONGINT loop_top = ORG_pc;
    codegen_gen(sASL, Accumulator, 0, 0);   // 1 byte
    codegen_gen(sDEX, Implied, 0, 0);       // 1 byte
    codegen_gen(sBNE, ProgramCounterRelative, loop_top, 0); // 2 bytes
    // A now has mask; AND with loaded value
    codegen_gen(sAND, DirectPage, reg_addr(x->r), 0);
    codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);
    RH -= 2;
  }
  SetCC(x, NE);
}

void ORG_Register(ORG_Item *x) {
  // RISC: Put0(Mov, RH, 0, x->a % 0x10);
  x->mode = Reg;
  x->r = RH;
  incR();
}

void ORG_HH(ORG_Item *x) {
  // RISC: Put0(Mov + U + (x->a % 2) * V, RH, 0, 0);
  x->mode = Reg;
  x->r = RH;
  incR();
}

void ORG_Adr(ORG_Item *x) {
    if ((x->mode == ORB_Var) || (x->mode == ORB_Par) || (x->mode == RegI)) {
      loadAdr(x);
      // loadAdr allocates 2 registers (address + bank), but ADR returns INTEGER
      // Release the bank register since we only need the 16-bit address
      RH--;
    } else if ((x->mode == ORB_Const) && (x->type->form == ORB_Proc)) {
	  load(x);
    } else if ((x->mode == ORB_Const) && (x->type->form == ORB_String)) {
	  loadStringAdr(x);
    } else if ((x->mode == ORB_Const) &&
               (x->type->form == ORB_Array || x->type->form == ORB_Record)) {
	  loadStringAdr(x);
    } else {
	  ORS_Mark("not addressable");
    }
}

void ORG_Bank(ORG_Item *x) {
  if (x->mode == ORB_Var || x->mode == ORB_Par || x->mode == RegI) {
    loadAdr(x);
    // loadAdr allocated 2 regs: [addr, bank]. Keep bank, drop addr.
    Set16(1, 1);
    codegen_gen(sLDA, DirectPage, reg_addr(x->r + 1), 0);
    codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);
    RH--;
  } else if (x->mode == ORB_Const &&
             (x->type->form == ORB_Array || x->type->form == ORB_Record ||
              x->type->form == ORB_String)) {
    // Same-module structured constant/string: own module's bank
    Set16(1, 1);
    codegen_gen(sLDA, DirectPage, BANK_DP, 0);
    codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);
    x->mode = Reg;
    x->r = RH;
    incR();
  } else {
    ORS_Mark("not addressable");
  }
}

void ORG_Condition(ORG_Item *x) {
  SetCC(x, x->a);
}

// Module management functions
void ORG_Open(INTEGER v) {
  ORG_pc = CODE_ORG;
  tdx = 0;
  strx = 0;
  RH = 0;
  fixorgP = 0;
  fixorgD = 0;
  fixorgT = 0;
  relocC = 0;
  td_fixupC = 0;
  for (int i = 0; i < FP_OPS; i++) fp_fixup_count[i] = 0;
  check = (v != 0);
  version = v;

  if (v == 0) {
	ORG_pc = 1;
	do {
	  code[ORG_pc] = 0;
	  ORG_pc++;
	} while (ORG_pc < 8);
  }
  longa = true; longi = true;
}

void ORG_SetDataSize(LONGINT dc) {
  ORG_varsize = dc;
}

void ORG_Header(void) {
  entry = ORG_pc;  // 65C816 uses byte addresses, no multiplication needed

  // Native mode, 16-bit registers, and SP are set by the emulator/boot loader.
  // Compiler assumes 16-bit A and X on entry.
  longa = true; longi = true;

  // SB initialisation — loader patches the $0000 to actual var_base
  reloc[relocC++] = ORG_pc;
  codegen_gen(sLDA, Immediate, 0x0000, 0);
  codegen_gen(sSTA, DirectPage, SB_DP, 0);

  // Bank initialisation — loader patches to actual data bank (0)
  reloc[relocC++] = ORG_pc | 0x80000000;  // bank reloc flag
  codegen_gen(sLDA, Immediate, 0x0000, 0);
  codegen_gen(sSTA, DirectPage, BANK_DP, 0);
}

static LONGINT NofPtrs(ORB_Type *typ) {
  ORB_Object *fld;
  LONGINT n;
  
  if ((typ->form == ORB_Pointer) || (typ->form == ORB_NilTyp)) {
	n = 1;
  } else if (typ->form == ORB_Record) {
	fld = typ->dsc;
	n = 0;
	while (fld != NULL) {
	  n = NofPtrs(fld->type) + n;
	  fld = fld->next;
	}
  } else if (typ->form == ORB_Array) {
	n = NofPtrs(typ->base) * typ->len;
  } else {
	n = 0;
  }
  return n;
}

static void FindPtrs(Files_Rider *R, ORB_Type *typ, LONGINT adr) {
  ORB_Object *fld;
  LONGINT i, s;
  
  if ((typ->form == ORB_Pointer) || (typ->form == ORB_NilTyp)) {
	Files_WriteInt(R, adr);
  } else if (typ->form == ORB_Record) {
	fld = typ->dsc;
	while (fld != NULL) {
	  FindPtrs(R, fld->type, fld->val + adr);
	  fld = fld->next;
	}
  } else if (typ->form == ORB_Array) {
	s = typ->base->size;
	for (i = 0; i < typ->len; i++) {
	  FindPtrs(R, typ->base, i * s + adr);
	}
  }
}

// ============================================================
// IEEE 754 Single-Precision Floating Point Subroutines
// ============================================================
// All subroutines use FP workspace at DP $22-$41.
// Operands in FP_A (result) and FP_B.
// Assumes 16-bit A and X (REP #$30) on entry.

// Patch a forward relative branch: writes offset at branchOperandAddr to reach current ORG_pc
static void patch(LONGINT branchOperandAddr) {
  code[branchOperandAddr - CODE_ORG] = (uint8_t)(ORG_pc - (branchOperandAddr + 1));
}
// Emit a forward branch with placeholder and return the operand address for later patching
static LONGINT emitFwdBranch(OpCode op) {
  codegen_gen(op, ProgramCounterRelative, ORG_pc + 2, 0);
  return ORG_pc - 1;
}

// --- FLOOR: IEEE 754 single → signed 16-bit integer ---
static void emitFP_FLOOR(void) {
  fp_sub_addr[FP_FLOOR] = ORG_pc;
  LONGINT p1, p2, p3, loop;

  // Extract sign
  codegen_gen(sLDA, DirectPage, FP_A_HI, 0);
  codegen_gen(sAND, Immediate, 0x8000, 0);
  codegen_gen(sSTA, DirectPage, FP_SIGN, 0);

  // Extract exponent = (FP_A_HI & 0x7F80) >> 7
  codegen_gen(sLDA, DirectPage, FP_A_HI, 0);
  codegen_gen(sAND, Immediate, 0x7F80, 0);
  // >>7: seven LSR A instructions
  for (int i = 0; i < 7; i++) codegen_gen(sLSR, Accumulator, 0, 0);
  codegen_gen(sSTA, DirectPage, FP_EXP, 0);

  // If exp == 0: subnormal or zero
  p1 = emitFwdBranch(sBNE);      // BNE → has_exp
  // exp==0: positive→0, negative→-1 (unless -0.0→0)
  codegen_gen(sLDA, DirectPage, FP_SIGN, 0);
  p2 = emitFwdBranch(sBEQ);      // BEQ → ret_zero
  // negative: check mantissa for -0.0
  codegen_gen(sLDA, DirectPage, FP_A_LO, 0);
  codegen_gen(sORA, DirectPage, FP_A_HI, 0);
  codegen_gen(sAND, Immediate, 0x7FFF, 0);
  p3 = emitFwdBranch(sBEQ);      // BEQ → ret_zero
  codegen_gen(sLDA, Immediate, 0xFFFF, 0);
  codegen_gen(sSTA, DirectPage, FP_A_LO, 0);
  codegen_gen(sRTS, Implied, 0, 0);
  // ret_zero:
  patch(p2); patch(p3);
  codegen_gen(sLDA, Immediate, 0x0000, 0);
  codegen_gen(sSTA, DirectPage, FP_A_LO, 0);
  codegen_gen(sRTS, Implied, 0, 0);

  // has_exp:
  patch(p1);
  // unbiased = exp - 127
  codegen_gen(sLDA, DirectPage, FP_EXP, 0);
  codegen_gen(sSEC, Implied, 0, 0);
  codegen_gen(sSBC, Immediate, 127, 0);
  codegen_gen(sSTA, DirectPage, FP_EXP, 0);

  // If unbiased < 0: |val| < 1 → positive:0, negative:-1
  p1 = emitFwdBranch(sBPL);      // BPL → normal
  codegen_gen(sLDA, DirectPage, FP_SIGN, 0);
  codegen_gen(sBNE, ProgramCounterRelative, ORG_pc + 2 + 5, 0); // BNE → neg1
  codegen_gen(sLDA, Immediate, 0x0000, 0);
  codegen_gen(sBRA, ProgramCounterRelative, ORG_pc + 2 + 3, 0); // BRA → store
  codegen_gen(sLDA, Immediate, 0xFFFF, 0);
  codegen_gen(sSTA, DirectPage, FP_A_LO, 0);
  codegen_gen(sRTS, Implied, 0, 0);
  patch(p1);

  // If unbiased >= 15: clamp
  codegen_gen(sCMP, Immediate, 15, 0);
  p1 = emitFwdBranch(sBCC);      // BCC → no_ovf
  codegen_gen(sLDA, DirectPage, FP_SIGN, 0);
  codegen_gen(sBNE, ProgramCounterRelative, ORG_pc + 2 + 5, 0); // BNE → neg_ovf
  codegen_gen(sLDA, Immediate, 0x7FFF, 0);
  codegen_gen(sBRA, ProgramCounterRelative, ORG_pc + 2 + 3, 0); // BRA → st_ovf
  codegen_gen(sLDA, Immediate, 0x8000, 0);
  codegen_gen(sSTA, DirectPage, FP_A_LO, 0);
  codegen_gen(sRTS, Implied, 0, 0);
  patch(p1);

  // Build 24-bit mantissa with implicit 1
  codegen_gen(sLDA, DirectPage, FP_A_HI, 0);
  codegen_gen(sAND, Immediate, 0x007F, 0);
  codegen_gen(sORA, Immediate, 0x0080, 0);
  codegen_gen(sSTA, DirectPage, FP_M1_HI, 0);
  codegen_gen(sLDA, DirectPage, FP_A_LO, 0);
  codegen_gen(sSTA, DirectPage, FP_M1_LO, 0);

  // Track fractional bits for FLOOR rounding
  codegen_gen(sSTZ, DirectPage, FP_TEMP, 0);

  // shift_count = 23 - unbiased (always > 0 since unbiased < 15)
  codegen_gen(sLDA, Immediate, 23, 0);
  codegen_gen(sSEC, Implied, 0, 0);
  codegen_gen(sSBC, DirectPage, FP_EXP, 0);
  p1 = emitFwdBranch(sBEQ);      // BEQ → done_shift
  codegen_gen(sSTA, DirectPage, FP_CNT, 0);

  loop = ORG_pc;
  codegen_gen(sLSR, DirectPage, FP_M1_HI, 0);
  codegen_gen(sROR, DirectPage, FP_M1_LO, 0);
  codegen_gen(sBCC, ProgramCounterRelative, ORG_pc + 2 + 2, 0); // BCC +2
  codegen_gen(sINC, DirectPage, FP_TEMP, 0);
  codegen_gen(sDEC, DirectPage, FP_CNT, 0);
  codegen_gen(sBNE, ProgramCounterRelative, loop, 0);
  patch(p1);                     // done_shift

  // Result in FP_M1_LO. Apply sign.
  codegen_gen(sLDA, DirectPage, FP_SIGN, 0);
  p1 = emitFwdBranch(sBNE);      // BNE → negative
  // positive: store directly
  codegen_gen(sLDA, DirectPage, FP_M1_LO, 0);
  codegen_gen(sSTA, DirectPage, FP_A_LO, 0);
  codegen_gen(sRTS, Implied, 0, 0);

  // negative: negate magnitude; if fractional bits, add 1 before negate
  patch(p1);
  codegen_gen(sLDA, DirectPage, FP_TEMP, 0);
  codegen_gen(sBEQ, ProgramCounterRelative, ORG_pc + 2 + 4, 0); // BEQ +4 (no fraction)
  codegen_gen(sINC, DirectPage, FP_M1_LO, 0);
  codegen_gen(sBRA, ProgramCounterRelative, ORG_pc + 2, 0); // BRA +0 (→ negate)
  // negate: two's complement
  codegen_gen(sLDA, DirectPage, FP_M1_LO, 0);
  codegen_gen(sEOR, Immediate, 0xFFFF, 0);
  codegen_gen(sINC, Accumulator, 0, 0);
  codegen_gen(sSTA, DirectPage, FP_A_LO, 0);
  codegen_gen(sRTS, Implied, 0, 0);
}

// --- FLT: signed 16-bit integer → IEEE 754 single ---
static void emitFP_FLT(void) {
  fp_sub_addr[FP_FLT] = ORG_pc;
  LONGINT p1, loop;

  // Input in FP_A_LO (16-bit signed integer)
  codegen_gen(sLDA, DirectPage, FP_A_LO, 0);

  // If zero, return +0.0
  p1 = emitFwdBranch(sBNE);      // BNE → nonzero
  codegen_gen(sSTZ, DirectPage, FP_A_HI, 0);
  codegen_gen(sRTS, Implied, 0, 0);
  patch(p1);

  // Save sign, take absolute value
  codegen_gen(sSTZ, DirectPage, FP_SIGN, 0);
  p1 = emitFwdBranch(sBPL);      // BPL → positive
  codegen_gen(sLDA, Immediate, 0x8000, 0);
  codegen_gen(sSTA, DirectPage, FP_SIGN, 0);
  codegen_gen(sLDA, DirectPage, FP_A_LO, 0);
  codegen_gen(sEOR, Immediate, 0xFFFF, 0);
  codegen_gen(sINC, Accumulator, 0, 0);
  codegen_gen(sBRA, ProgramCounterRelative, ORG_pc + 2 + 2, 0); // BRA → store_abs
  patch(p1);
  codegen_gen(sLDA, DirectPage, FP_A_LO, 0);
  // store_abs:
  codegen_gen(sSTA, DirectPage, FP_M1_LO, 0);
  codegen_gen(sSTZ, DirectPage, FP_M1_HI, 0);

  // Find highest bit: shift left until bit 15 is set, count shifts
  codegen_gen(sLDA, Immediate, 0, 0);
  codegen_gen(sSTA, DirectPage, FP_CNT, 0);
  codegen_gen(sLDA, DirectPage, FP_M1_LO, 0);

  loop = ORG_pc;
  codegen_gen(sCMP, Immediate, 0x8000, 0);
  p1 = emitFwdBranch(sBCS);      // BCS → found_msb
  codegen_gen(sASL, Accumulator, 0, 0);
  codegen_gen(sINC, DirectPage, FP_CNT, 0);
  codegen_gen(sBRA, ProgramCounterRelative, loop, 0);
  patch(p1);

  // A now has the value shifted so bit 15 is the MSB
  codegen_gen(sSTA, DirectPage, FP_TEMP, 0);
  // mantissa_lo = (TEMP & 0xFF) << 8
  codegen_gen(sAND, Immediate, 0x00FF, 0);
  codegen_gen(sXBA, Implied, 0, 0);
  codegen_gen(sSTA, DirectPage, FP_A_LO, 0);

  // mantissa_hi = (TEMP >> 8) & 0x7F
  codegen_gen(sLDA, DirectPage, FP_TEMP, 0);
  codegen_gen(sXBA, Implied, 0, 0);
  codegen_gen(sAND, Immediate, 0x007F, 0);

  // exponent = 127 + 15 - shift_count
  codegen_gen(sSTA, DirectPage, FP_TEMP, 0);
  codegen_gen(sLDA, Immediate, 127 + 15, 0);
  codegen_gen(sSEC, Implied, 0, 0);
  codegen_gen(sSBC, DirectPage, FP_CNT, 0);
  // Shift exp left 7: XBA (<<8) then LSR (>>1) = <<7
  codegen_gen(sXBA, Implied, 0, 0);
  codegen_gen(sLSR, Accumulator, 0, 0);
  codegen_gen(sAND, Immediate, 0x7F80, 0);
  codegen_gen(sORA, DirectPage, FP_TEMP, 0);
  codegen_gen(sORA, DirectPage, FP_SIGN, 0);
  codegen_gen(sSTA, DirectPage, FP_A_HI, 0);
  codegen_gen(sRTS, Implied, 0, 0);
}

// --- FADD: IEEE 754 single addition ---
// FP_A + FP_B → FP_A
static void emitFP_ADD(void) {
  fp_sub_addr[FP_ADD] = ORG_pc;
  LONGINT p1, p2, p3, loop;

  // Unpack A: sign_a, exp_a, mant_a (24-bit with implicit 1)
  // Check for zero first
  codegen_gen(sLDA, DirectPage, FP_A_LO, 0);
  codegen_gen(sORA, DirectPage, FP_A_HI, 0);
  codegen_gen(sAND, Immediate, 0x7FFF, 0);
  p1 = emitFwdBranch(sBNE);      // BNE → a_nonzero
  // A is zero: return B
  codegen_gen(sLDA, DirectPage, FP_B_LO, 0);
  codegen_gen(sSTA, DirectPage, FP_A_LO, 0);
  codegen_gen(sLDA, DirectPage, FP_B_HI, 0);
  codegen_gen(sSTA, DirectPage, FP_A_HI, 0);
  codegen_gen(sRTS, Implied, 0, 0);
  patch(p1);

  // Check B for zero
  codegen_gen(sLDA, DirectPage, FP_B_LO, 0);
  codegen_gen(sORA, DirectPage, FP_B_HI, 0);
  codegen_gen(sAND, Immediate, 0x7FFF, 0);
  p1 = emitFwdBranch(sBNE);      // BNE → b_nonzero
  codegen_gen(sRTS, Implied, 0, 0);
  patch(p1);

  // Extract sign_a
  codegen_gen(sLDA, DirectPage, FP_A_HI, 0);
  codegen_gen(sAND, Immediate, 0x8000, 0);
  codegen_gen(sSTA, DirectPage, FP_SIGN, 0);

  // Extract exp_a
  codegen_gen(sLDA, DirectPage, FP_A_HI, 0);
  codegen_gen(sAND, Immediate, 0x7F80, 0);
  for (int i = 0; i < 7; i++) codegen_gen(sLSR, Accumulator, 0, 0);
  codegen_gen(sSTA, DirectPage, FP_EXP, 0);

  // Extract mant_a (24-bit with implicit 1)
  codegen_gen(sLDA, DirectPage, FP_A_HI, 0);
  codegen_gen(sAND, Immediate, 0x007F, 0);
  codegen_gen(sORA, Immediate, 0x0080, 0);
  codegen_gen(sSTA, DirectPage, FP_M1_HI, 0);
  codegen_gen(sLDA, DirectPage, FP_A_LO, 0);
  codegen_gen(sSTA, DirectPage, FP_M1_LO, 0);

  // Extract sign_b
  codegen_gen(sLDA, DirectPage, FP_B_HI, 0);
  codegen_gen(sAND, Immediate, 0x8000, 0);
  codegen_gen(sSTA, DirectPage, FP_TEMP2, 0);

  // Extract exp_b
  codegen_gen(sLDA, DirectPage, FP_B_HI, 0);
  codegen_gen(sAND, Immediate, 0x7F80, 0);
  for (int i = 0; i < 7; i++) codegen_gen(sLSR, Accumulator, 0, 0);
  codegen_gen(sSTA, DirectPage, FP_TEMP, 0);

  // Extract mant_b
  codegen_gen(sLDA, DirectPage, FP_B_HI, 0);
  codegen_gen(sAND, Immediate, 0x007F, 0);
  codegen_gen(sORA, Immediate, 0x0080, 0);
  codegen_gen(sSTA, DirectPage, FP_M2_HI, 0);
  codegen_gen(sLDA, DirectPage, FP_B_LO, 0);
  codegen_gen(sSTA, DirectPage, FP_M2_LO, 0);

  // Compare exponents: ensure exp_a >= exp_b (swap if needed)
  codegen_gen(sLDA, DirectPage, FP_EXP, 0);
  codegen_gen(sCMP, DirectPage, FP_TEMP, 0);
  p1 = emitFwdBranch(sBCS);      // BCS → no_swap

  // Swap A and B (exp, mant, sign)
  // Swap exponents
  codegen_gen(sLDA, DirectPage, FP_EXP, 0);
  codegen_gen(sLDX, DirectPage, FP_TEMP, 0);
  codegen_gen(sSTX, DirectPage, FP_EXP, 0);
  codegen_gen(sSTA, DirectPage, FP_TEMP, 0);
  // Swap mantissas
  codegen_gen(sLDA, DirectPage, FP_M1_LO, 0);
  codegen_gen(sLDX, DirectPage, FP_M2_LO, 0);
  codegen_gen(sSTX, DirectPage, FP_M1_LO, 0);
  codegen_gen(sSTA, DirectPage, FP_M2_LO, 0);
  codegen_gen(sLDA, DirectPage, FP_M1_HI, 0);
  codegen_gen(sLDX, DirectPage, FP_M2_HI, 0);
  codegen_gen(sSTX, DirectPage, FP_M1_HI, 0);
  codegen_gen(sSTA, DirectPage, FP_M2_HI, 0);
  // Swap signs
  codegen_gen(sLDA, DirectPage, FP_SIGN, 0);
  codegen_gen(sLDX, DirectPage, FP_TEMP2, 0);
  codegen_gen(sSTX, DirectPage, FP_SIGN, 0);
  codegen_gen(sSTA, DirectPage, FP_TEMP2, 0);
  patch(p1);                     // no_swap

  // Align mantissas: shift M2 right by (exp_a - exp_b)
  codegen_gen(sLDA, DirectPage, FP_EXP, 0);
  codegen_gen(sSEC, Implied, 0, 0);
  codegen_gen(sSBC, DirectPage, FP_TEMP, 0);
  p1 = emitFwdBranch(sBEQ);      // BEQ → aligned (no shift needed)
  // If shift >= 24, M2 becomes zero
  codegen_gen(sCMP, Immediate, 24, 0);
  p2 = emitFwdBranch(sBCC);      // BCC → do_shift
  codegen_gen(sSTZ, DirectPage, FP_M2_LO, 0);
  codegen_gen(sSTZ, DirectPage, FP_M2_HI, 0);
  p3 = emitFwdBranch(sBRA);      // BRA → aligned
  patch(p2);
  codegen_gen(sSTA, DirectPage, FP_CNT, 0);
  loop = ORG_pc;
  codegen_gen(sLSR, DirectPage, FP_M2_HI, 0);
  codegen_gen(sROR, DirectPage, FP_M2_LO, 0);
  codegen_gen(sDEC, DirectPage, FP_CNT, 0);
  codegen_gen(sBNE, ProgramCounterRelative, loop, 0);
  patch(p1); patch(p3);          // aligned

  // Compare signs
  codegen_gen(sLDA, DirectPage, FP_SIGN, 0);
  codegen_gen(sEOR, DirectPage, FP_TEMP2, 0);
  p1 = emitFwdBranch(sBNE);      // BNE → diff_signs

  // Same signs: add mantissas
  codegen_gen(sCLC, Implied, 0, 0);
  codegen_gen(sLDA, DirectPage, FP_M1_LO, 0);
  codegen_gen(sADC, DirectPage, FP_M2_LO, 0);
  codegen_gen(sSTA, DirectPage, FP_M1_LO, 0);
  codegen_gen(sLDA, DirectPage, FP_M1_HI, 0);
  codegen_gen(sADC, DirectPage, FP_M2_HI, 0);
  codegen_gen(sSTA, DirectPage, FP_M1_HI, 0);
  // Check for mantissa overflow (bit 8 of M1_HI = bit 24 of 24-bit mantissa)
  codegen_gen(sLDA, DirectPage, FP_M1_HI, 0);
  codegen_gen(sAND, Immediate, 0x0100, 0);
  p2 = emitFwdBranch(sBEQ);      // BEQ → no_overflow
  // Shift right 1, increment exp
  codegen_gen(sLSR, DirectPage, FP_M1_HI, 0);
  codegen_gen(sROR, DirectPage, FP_M1_LO, 0);
  codegen_gen(sINC, DirectPage, FP_EXP, 0);
  patch(p2);
  p2 = emitFwdBranch(sBRA);      // BRA → pack
  patch(p1);                     // diff_signs

  // Different signs: subtract smaller from larger (M1 >= M2 after exponent alignment)
  codegen_gen(sSEC, Implied, 0, 0);
  codegen_gen(sLDA, DirectPage, FP_M1_LO, 0);
  codegen_gen(sSBC, DirectPage, FP_M2_LO, 0);
  codegen_gen(sSTA, DirectPage, FP_M1_LO, 0);
  codegen_gen(sLDA, DirectPage, FP_M1_HI, 0);
  codegen_gen(sSBC, DirectPage, FP_M2_HI, 0);
  codegen_gen(sSTA, DirectPage, FP_M1_HI, 0);

  // Check if result is zero
  codegen_gen(sORA, DirectPage, FP_M1_LO, 0);
  p3 = emitFwdBranch(sBNE);      // BNE → normalize
  // Result is zero
  codegen_gen(sSTZ, DirectPage, FP_A_LO, 0);
  codegen_gen(sSTZ, DirectPage, FP_A_HI, 0);
  codegen_gen(sRTS, Implied, 0, 0);
  patch(p3);

  // Normalize: shift left until bit 7 of M1_HI is set (bit 23 of mantissa)
  loop = ORG_pc;
  codegen_gen(sLDA, DirectPage, FP_M1_HI, 0);
  codegen_gen(sAND, Immediate, 0x0080, 0);
  p3 = emitFwdBranch(sBNE);      // BNE → normalized (done)
  codegen_gen(sASL, DirectPage, FP_M1_LO, 0);
  codegen_gen(sROL, DirectPage, FP_M1_HI, 0);
  codegen_gen(sDEC, DirectPage, FP_EXP, 0);
  codegen_gen(sBRA, ProgramCounterRelative, loop, 0);
  patch(p3);
  patch(p2);                     // pack

  // Pack result: FP_A_HI = sign | (exp << 7) | (M1_HI & 0x7F)
  //              FP_A_LO = M1_LO
  codegen_gen(sLDA, DirectPage, FP_EXP, 0);
  codegen_gen(sXBA, Implied, 0, 0);
  codegen_gen(sLSR, Accumulator, 0, 0);
  codegen_gen(sAND, Immediate, 0x7F80, 0);
  codegen_gen(sSTA, DirectPage, FP_A_HI, 0);
  codegen_gen(sLDA, DirectPage, FP_M1_HI, 0);
  codegen_gen(sAND, Immediate, 0x007F, 0);
  codegen_gen(sORA, DirectPage, FP_A_HI, 0);
  codegen_gen(sORA, DirectPage, FP_SIGN, 0);
  codegen_gen(sSTA, DirectPage, FP_A_HI, 0);
  codegen_gen(sLDA, DirectPage, FP_M1_LO, 0);
  codegen_gen(sSTA, DirectPage, FP_A_LO, 0);
  codegen_gen(sRTS, Implied, 0, 0);
}

// --- FMUL: IEEE 754 single multiplication ---
// FP_A * FP_B → FP_A
static void emitFP_MUL(void) {
  fp_sub_addr[FP_MUL] = ORG_pc;
  LONGINT p1, p2, loop;

  // Check A for zero
  codegen_gen(sLDA, DirectPage, FP_A_LO, 0);
  codegen_gen(sORA, DirectPage, FP_A_HI, 0);
  codegen_gen(sAND, Immediate, 0x7FFF, 0);
  p1 = emitFwdBranch(sBNE);      // BNE → a_nz
  codegen_gen(sSTZ, DirectPage, FP_A_LO, 0);
  codegen_gen(sSTZ, DirectPage, FP_A_HI, 0);
  codegen_gen(sRTS, Implied, 0, 0);
  patch(p1);

  // Check B for zero
  codegen_gen(sLDA, DirectPage, FP_B_LO, 0);
  codegen_gen(sORA, DirectPage, FP_B_HI, 0);
  codegen_gen(sAND, Immediate, 0x7FFF, 0);
  p1 = emitFwdBranch(sBNE);      // BNE → b_nz
  codegen_gen(sSTZ, DirectPage, FP_A_LO, 0);
  codegen_gen(sSTZ, DirectPage, FP_A_HI, 0);
  codegen_gen(sRTS, Implied, 0, 0);
  patch(p1);

  // Result sign = sign_a XOR sign_b
  codegen_gen(sLDA, DirectPage, FP_A_HI, 0);
  codegen_gen(sEOR, DirectPage, FP_B_HI, 0);
  codegen_gen(sAND, Immediate, 0x8000, 0);
  codegen_gen(sSTA, DirectPage, FP_SIGN, 0);

  // Result exp = exp_a + exp_b - 127
  codegen_gen(sLDA, DirectPage, FP_A_HI, 0);
  codegen_gen(sAND, Immediate, 0x7F80, 0);
  for (int i = 0; i < 7; i++) codegen_gen(sLSR, Accumulator, 0, 0);
  codegen_gen(sSTA, DirectPage, FP_EXP, 0);

  codegen_gen(sLDA, DirectPage, FP_B_HI, 0);
  codegen_gen(sAND, Immediate, 0x7F80, 0);
  for (int i = 0; i < 7; i++) codegen_gen(sLSR, Accumulator, 0, 0);
  codegen_gen(sCLC, Implied, 0, 0);
  codegen_gen(sADC, DirectPage, FP_EXP, 0);
  codegen_gen(sSEC, Implied, 0, 0);
  codegen_gen(sSBC, Immediate, 127, 0);
  codegen_gen(sSTA, DirectPage, FP_EXP, 0);

  // Extract mantissa A (24-bit)
  codegen_gen(sLDA, DirectPage, FP_A_HI, 0);
  codegen_gen(sAND, Immediate, 0x007F, 0);
  codegen_gen(sORA, Immediate, 0x0080, 0);
  codegen_gen(sSTA, DirectPage, FP_M1_HI, 0);
  codegen_gen(sLDA, DirectPage, FP_A_LO, 0);
  codegen_gen(sSTA, DirectPage, FP_M1_LO, 0);

  // Extract mantissa B (24-bit)
  codegen_gen(sLDA, DirectPage, FP_B_HI, 0);
  codegen_gen(sAND, Immediate, 0x007F, 0);
  codegen_gen(sORA, Immediate, 0x0080, 0);
  codegen_gen(sSTA, DirectPage, FP_M2_HI, 0);
  codegen_gen(sLDA, DirectPage, FP_B_LO, 0);
  codegen_gen(sSTA, DirectPage, FP_M2_LO, 0);

  // 24x24 multiply: shift-and-add into PROD2:PROD1:PROD0 (48-bit result)
  codegen_gen(sSTZ, DirectPage, FP_PROD0, 0);
  codegen_gen(sSTZ, DirectPage, FP_PROD1, 0);
  codegen_gen(sSTZ, DirectPage, FP_PROD2, 0);
  codegen_gen(sLDA, Immediate, 24, 0);
  codegen_gen(sSTA, DirectPage, FP_CNT, 0);

  loop = ORG_pc;
  // Check LSB of M2
  codegen_gen(sLDA, DirectPage, FP_M2_LO, 0);
  codegen_gen(sAND, Immediate, 0x0001, 0);
  p1 = emitFwdBranch(sBEQ);      // BEQ → no_add
  // Add M1 to PROD (48-bit add)
  codegen_gen(sCLC, Implied, 0, 0);
  codegen_gen(sLDA, DirectPage, FP_PROD0, 0);
  codegen_gen(sADC, DirectPage, FP_M1_LO, 0);
  codegen_gen(sSTA, DirectPage, FP_PROD0, 0);
  codegen_gen(sLDA, DirectPage, FP_PROD1, 0);
  codegen_gen(sADC, DirectPage, FP_M1_HI, 0);
  codegen_gen(sSTA, DirectPage, FP_PROD1, 0);
  codegen_gen(sBCC, ProgramCounterRelative, ORG_pc + 2 + 2, 0); // BCC +2
  codegen_gen(sINC, DirectPage, FP_PROD2, 0);
  patch(p1);                     // no_add

  // Shift M2 right by 1
  codegen_gen(sLSR, DirectPage, FP_M2_HI, 0);
  codegen_gen(sROR, DirectPage, FP_M2_LO, 0);
  // Shift PROD right by 1
  codegen_gen(sLSR, DirectPage, FP_PROD2, 0);
  codegen_gen(sROR, DirectPage, FP_PROD1, 0);
  codegen_gen(sROR, DirectPage, FP_PROD0, 0);

  codegen_gen(sDEC, DirectPage, FP_CNT, 0);
  codegen_gen(sBNE, ProgramCounterRelative, loop, 0);

  // After 24 right-shifts, PROD = (M1 * M2) >> 24.
  // If PROD1 bit 7 set: mantissa at bit 23, need INC EXP
  // If PROD1 bit 7 clear: mantissa at bit 22, shift left 1
  codegen_gen(sLDA, DirectPage, FP_PROD1, 0);
  codegen_gen(sAND, Immediate, 0x0080, 0);
  p1 = emitFwdBranch(sBEQ);      // BEQ → shift_up
  // PROD1 bit 7 set: product overflow, increment exponent
  codegen_gen(sINC, DirectPage, FP_EXP, 0);
  p2 = emitFwdBranch(sBRA);      // BRA → pack
  patch(p1);                     // shift_up:
  codegen_gen(sASL, DirectPage, FP_PROD0, 0);
  codegen_gen(sROL, DirectPage, FP_PROD1, 0);
  patch(p2);                     // pack:

  // Pack: FP_A_HI = sign | (exp << 7) | (PROD1 & 0x7F), FP_A_LO = PROD0
  codegen_gen(sLDA, DirectPage, FP_EXP, 0);
  codegen_gen(sXBA, Implied, 0, 0);
  codegen_gen(sLSR, Accumulator, 0, 0);
  codegen_gen(sAND, Immediate, 0x7F80, 0);
  codegen_gen(sSTA, DirectPage, FP_A_HI, 0);
  codegen_gen(sLDA, DirectPage, FP_PROD1, 0);
  codegen_gen(sAND, Immediate, 0x007F, 0);
  codegen_gen(sORA, DirectPage, FP_A_HI, 0);
  codegen_gen(sORA, DirectPage, FP_SIGN, 0);
  codegen_gen(sSTA, DirectPage, FP_A_HI, 0);
  codegen_gen(sLDA, DirectPage, FP_PROD0, 0);
  codegen_gen(sSTA, DirectPage, FP_A_LO, 0);
  codegen_gen(sRTS, Implied, 0, 0);
}

// --- FDIV: IEEE 754 single division ---
// FP_A / FP_B → FP_A
static void emitFP_DIV(void) {
  fp_sub_addr[FP_DIV] = ORG_pc;
  LONGINT p1, p2, loop;

  // Check B for zero → trap
  codegen_gen(sLDA, DirectPage, FP_B_LO, 0);
  codegen_gen(sORA, DirectPage, FP_B_HI, 0);
  codegen_gen(sAND, Immediate, 0x7FFF, 0);
  p1 = emitFwdBranch(sBNE);      // BNE → b_nz
  codegen_gen(sBRK, Immediate, 7, 0); // BRK #7 (division by zero trap)
  patch(p1);

  // Check A for zero
  codegen_gen(sLDA, DirectPage, FP_A_LO, 0);
  codegen_gen(sORA, DirectPage, FP_A_HI, 0);
  codegen_gen(sAND, Immediate, 0x7FFF, 0);
  p1 = emitFwdBranch(sBNE);      // BNE → a_nz
  codegen_gen(sSTZ, DirectPage, FP_A_LO, 0);
  codegen_gen(sSTZ, DirectPage, FP_A_HI, 0);
  codegen_gen(sRTS, Implied, 0, 0);
  patch(p1);

  // Result sign = sign_a XOR sign_b
  codegen_gen(sLDA, DirectPage, FP_A_HI, 0);
  codegen_gen(sEOR, DirectPage, FP_B_HI, 0);
  codegen_gen(sAND, Immediate, 0x8000, 0);
  codegen_gen(sSTA, DirectPage, FP_SIGN, 0);

  // Result exp = exp_a - exp_b + 127
  codegen_gen(sLDA, DirectPage, FP_A_HI, 0);
  codegen_gen(sAND, Immediate, 0x7F80, 0);
  for (int i = 0; i < 7; i++) codegen_gen(sLSR, Accumulator, 0, 0);
  codegen_gen(sSTA, DirectPage, FP_EXP, 0);

  codegen_gen(sLDA, DirectPage, FP_B_HI, 0);
  codegen_gen(sAND, Immediate, 0x7F80, 0);
  for (int i = 0; i < 7; i++) codegen_gen(sLSR, Accumulator, 0, 0);
  codegen_gen(sSTA, DirectPage, FP_TEMP, 0);

  codegen_gen(sLDA, DirectPage, FP_EXP, 0);
  codegen_gen(sSEC, Implied, 0, 0);
  codegen_gen(sSBC, DirectPage, FP_TEMP, 0);
  codegen_gen(sCLC, Implied, 0, 0);
  codegen_gen(sADC, Immediate, 127, 0);
  codegen_gen(sSTA, DirectPage, FP_EXP, 0);

  // Extract mantissa A (dividend) into M1
  codegen_gen(sLDA, DirectPage, FP_A_HI, 0);
  codegen_gen(sAND, Immediate, 0x007F, 0);
  codegen_gen(sORA, Immediate, 0x0080, 0);
  codegen_gen(sSTA, DirectPage, FP_M1_HI, 0);
  codegen_gen(sLDA, DirectPage, FP_A_LO, 0);
  codegen_gen(sSTA, DirectPage, FP_M1_LO, 0);

  // Extract mantissa B (divisor) into M2
  codegen_gen(sLDA, DirectPage, FP_B_HI, 0);
  codegen_gen(sAND, Immediate, 0x007F, 0);
  codegen_gen(sORA, Immediate, 0x0080, 0);
  codegen_gen(sSTA, DirectPage, FP_M2_HI, 0);
  codegen_gen(sLDA, DirectPage, FP_B_LO, 0);
  codegen_gen(sSTA, DirectPage, FP_M2_LO, 0);

  // Restoring division (SANE-style): compare first, ROL quotient, then shift
  codegen_gen(sSTZ, DirectPage, FP_PROD0, 0);
  codegen_gen(sSTZ, DirectPage, FP_PROD1, 0);
  codegen_gen(sLDA, Immediate, 24, 0);
  codegen_gen(sSTA, DirectPage, FP_CNT, 0);

  loop = ORG_pc;
  // Step 1: Try subtract remainder - divisor
  codegen_gen(sSEC, Implied, 0, 0);
  codegen_gen(sLDA, DirectPage, FP_M1_LO, 0);
  codegen_gen(sSBC, DirectPage, FP_M2_LO, 0);
  codegen_gen(sSTA, DirectPage, FP_TEMP, 0);
  codegen_gen(sLDA, DirectPage, FP_M1_HI, 0);
  codegen_gen(sSBC, DirectPage, FP_M2_HI, 0);
  // If borrow (C=0): remainder < divisor
  p1 = emitFwdBranch(sBCC);      // BCC → no_sub
  // No borrow (C=1): commit subtraction
  codegen_gen(sSTA, DirectPage, FP_M1_HI, 0);
  codegen_gen(sLDA, DirectPage, FP_TEMP, 0);
  codegen_gen(sSTA, DirectPage, FP_M1_LO, 0);
  patch(p1);                     // no_sub: C=0 if skipped, C=1 if subtracted

  // Step 2: Shift carry into quotient (1=subtracted, 0=not)
  codegen_gen(sROL, DirectPage, FP_PROD0, 0);
  codegen_gen(sROL, DirectPage, FP_PROD1, 0);

  // Step 3: Shift remainder left for next iteration
  codegen_gen(sASL, DirectPage, FP_M1_LO, 0);
  codegen_gen(sROL, DirectPage, FP_M1_HI, 0);

  codegen_gen(sDEC, DirectPage, FP_CNT, 0);
  codegen_gen(sBNE, ProgramCounterRelative, loop, 0);

  // Quotient in PROD1:PROD0 (24-bit). Normalize if needed.
  // Check bit 23 (PROD1 bit 7)
  codegen_gen(sLDA, DirectPage, FP_PROD1, 0);
  codegen_gen(sAND, Immediate, 0x0080, 0);
  p1 = emitFwdBranch(sBNE);      // BNE → pack

  // Normalize: shift left until bit 23 set
  loop = ORG_pc;
  codegen_gen(sLDA, DirectPage, FP_PROD1, 0);
  codegen_gen(sAND, Immediate, 0x0080, 0);
  p2 = emitFwdBranch(sBNE);      // BNE → pack2
  codegen_gen(sASL, DirectPage, FP_PROD0, 0);
  codegen_gen(sROL, DirectPage, FP_PROD1, 0);
  codegen_gen(sDEC, DirectPage, FP_EXP, 0);
  codegen_gen(sBRA, ProgramCounterRelative, loop, 0);
  patch(p1); patch(p2);

  // Pack result
  codegen_gen(sLDA, DirectPage, FP_EXP, 0);
  codegen_gen(sXBA, Implied, 0, 0);
  codegen_gen(sLSR, Accumulator, 0, 0);
  codegen_gen(sAND, Immediate, 0x7F80, 0);
  codegen_gen(sSTA, DirectPage, FP_A_HI, 0);
  codegen_gen(sLDA, DirectPage, FP_PROD1, 0);
  codegen_gen(sAND, Immediate, 0x007F, 0);
  codegen_gen(sORA, DirectPage, FP_A_HI, 0);
  codegen_gen(sORA, DirectPage, FP_SIGN, 0);
  codegen_gen(sSTA, DirectPage, FP_A_HI, 0);
  codegen_gen(sLDA, DirectPage, FP_PROD0, 0);
  codegen_gen(sSTA, DirectPage, FP_A_LO, 0);
  codegen_gen(sRTS, Implied, 0, 0);
}

// --- FCMP: IEEE 754 single comparison → -1/0/+1 in FP_A_LO ---
static void emitFP_CMP(void) {
  fp_sub_addr[FP_CMP] = ORG_pc;
  LONGINT p1, p2;

  // Both zero check
  codegen_gen(sLDA, DirectPage, FP_A_LO, 0);
  codegen_gen(sORA, DirectPage, FP_A_HI, 0);
  codegen_gen(sAND, Immediate, 0x7FFF, 0);
  codegen_gen(sSTA, DirectPage, FP_TEMP, 0);
  codegen_gen(sLDA, DirectPage, FP_B_LO, 0);
  codegen_gen(sORA, DirectPage, FP_B_HI, 0);
  codegen_gen(sAND, Immediate, 0x7FFF, 0);
  codegen_gen(sORA, DirectPage, FP_TEMP, 0);
  p1 = emitFwdBranch(sBNE);      // BNE → not_both_zero
  codegen_gen(sLDA, Immediate, 0, 0);
  codegen_gen(sSTA, DirectPage, FP_A_LO, 0);
  codegen_gen(sRTS, Implied, 0, 0);
  patch(p1);

  // Sign comparison
  codegen_gen(sLDA, DirectPage, FP_A_HI, 0);
  codegen_gen(sAND, Immediate, 0x8000, 0);
  codegen_gen(sSTA, DirectPage, FP_SIGN, 0);
  codegen_gen(sLDA, DirectPage, FP_B_HI, 0);
  codegen_gen(sAND, Immediate, 0x8000, 0);
  codegen_gen(sCMP, DirectPage, FP_SIGN, 0);
  p1 = emitFwdBranch(sBEQ);      // BEQ → same_sign

  // Different signs
  codegen_gen(sLDA, DirectPage, FP_SIGN, 0);
  codegen_gen(sBNE, ProgramCounterRelative, ORG_pc + 2 + 5, 0); // BNE → a is neg
  codegen_gen(sLDA, Immediate, 1, 0);
  codegen_gen(sBRA, ProgramCounterRelative, ORG_pc + 2 + 3, 0);
  codegen_gen(sLDA, Immediate, 0xFFFF, 0);
  codegen_gen(sSTA, DirectPage, FP_A_LO, 0);
  codegen_gen(sRTS, Implied, 0, 0);
  patch(p1);

  // Same sign: compare hi magnitude
  codegen_gen(sLDA, DirectPage, FP_A_HI, 0);
  codegen_gen(sAND, Immediate, 0x7FFF, 0);
  codegen_gen(sSTA, DirectPage, FP_TEMP, 0);
  codegen_gen(sLDA, DirectPage, FP_B_HI, 0);
  codegen_gen(sAND, Immediate, 0x7FFF, 0);
  codegen_gen(sCMP, DirectPage, FP_TEMP, 0);
  p1 = emitFwdBranch(sBEQ);      // BEQ → hi_equal

  // Hi words differ: B < A means A > B (for positive)
  p2 = emitFwdBranch(sBCC);      // BCC → B < A (carry clear)
  // B > A
  codegen_gen(sLDA, Immediate, 0xFFFF, 0);
  codegen_gen(sBRA, ProgramCounterRelative, ORG_pc + 2 + 3, 0);
  patch(p2);
  codegen_gen(sLDA, Immediate, 1, 0);
  // If negative, reverse
  codegen_gen(sBIT, DirectPage, FP_SIGN, 0);
  p2 = emitFwdBranch(sBPL);      // BPL → store (positive, no reverse)
  // Negate result
  codegen_gen(sEOR, Immediate, 0xFFFF, 0);
  codegen_gen(sINC, Accumulator, 0, 0);
  patch(p2);
  codegen_gen(sSTA, DirectPage, FP_A_LO, 0);
  codegen_gen(sRTS, Implied, 0, 0);
  patch(p1);                     // hi_equal

  // Compare lo words
  codegen_gen(sLDA, DirectPage, FP_A_LO, 0);
  codegen_gen(sCMP, DirectPage, FP_B_LO, 0);
  p1 = emitFwdBranch(sBEQ);      // BEQ → equal
  p2 = emitFwdBranch(sBCC);      // BCC → A < B
  // A > B
  codegen_gen(sLDA, Immediate, 1, 0);
  codegen_gen(sBRA, ProgramCounterRelative, ORG_pc + 2 + 3, 0);
  patch(p2);
  // A < B
  codegen_gen(sLDA, Immediate, 0xFFFF, 0);
  // If negative, reverse
  codegen_gen(sBIT, DirectPage, FP_SIGN, 0);
  p2 = emitFwdBranch(sBPL);      // BPL → store
  codegen_gen(sEOR, Immediate, 0xFFFF, 0);
  codegen_gen(sINC, Accumulator, 0, 0);
  patch(p2);
  codegen_gen(sSTA, DirectPage, FP_A_LO, 0);
  codegen_gen(sRTS, Implied, 0, 0);
  patch(p1);                     // equal
  codegen_gen(sLDA, Immediate, 0, 0);
  codegen_gen(sSTA, DirectPage, FP_A_LO, 0);
  codegen_gen(sRTS, Implied, 0, 0);
}

static void emitFPSubroutines(void) {
  if (fp_fixup_count[FP_FLOOR] > 0) emitFP_FLOOR();
  if (fp_fixup_count[FP_FLT] > 0) emitFP_FLT();
  if (fp_fixup_count[FP_ADD] > 0) emitFP_ADD();
  if (fp_fixup_count[FP_MUL] > 0) emitFP_MUL();
  if (fp_fixup_count[FP_DIV] > 0) emitFP_DIV();
  if (fp_fixup_count[FP_CMP] > 0) emitFP_CMP();
}

static void fixupFPCalls(void) {
  for (int op = 0; op < FP_OPS; op++) {
    for (int i = 0; i < fp_fixup_count[op]; i++) {
      LONGINT pos = fp_fixups[op][i] - CODE_ORG;
      LONGINT addr = fp_sub_addr[op];
      code[pos] = addr & 0xFF;
      code[pos + 1] = (addr >> 8) & 0xFF;
    }
  }
}

void ORG_Close(ORS_Ident modid, LONGINT key, LONGINT nofent) {
  ORB_Object *obj;
  LONGINT i, comsize, nofimps, nofptrs, size;
  char name[256];
  Files_File *F;
  Files_Rider R;
  
  // Exit code
  // 65C816: Return to system - emulator calls main with JSL so return with RTL
  codegen_gen(sRTL, Implied, 0, 0);

  // Emit FP subroutines (if any used) and fixup JSR placeholders
  emitFPSubroutines();
  fixupFPCalls();

  obj = topScope->next;
  nofimps = 0;
  comsize = 4;
  nofptrs = 0;
  
  while (obj != NULL) {
	if ((obj->class == ORB_Mod) && (obj->dsc != systemScope)) {
	  nofimps++;
	} else if ((obj->exno != 0) && (obj->class == ORB_Const) && 
			   (obj->type->form == ORB_Proc) && (obj->type->nofpar == 0) && 
			   (obj->type->base == noType)) {
	  i = 0;
	  while (obj->name[i] != 0) i++;
	  i = (i + 4) / 4 * 4;
	  comsize += i + 4;
	} else if (obj->class == ORB_Var) {
	  nofptrs += NofPtrs(obj->type);
	}
	obj = obj->next;
  }
  
  size = ORG_varsize + strx + comsize + (ORG_pc + nofimps + nofent + nofptrs + 1) * 4;
  
  MakeFileName(name, modid, ".816");
  F = Files_New(name);
  Files_Set(&R, F, 0);
  Files_WriteString(&R, modid);
  Files_WriteInt(&R, key);
  Files_Write(&R, (char)version);
  Files_WriteInt(&R, size);
  
  obj = topScope->next;
  while ((obj != NULL) && (obj->class == ORB_Mod)) {
	if (obj->dsc != systemScope) {
	  Files_WriteString(&R, ((ORB_Module*)obj)->orgname);
	  Files_WriteInt(&R, obj->val);
	}
	obj = obj->next;
  }
  Files_Write(&R, 0);
  
  Files_WriteInt(&R, tdx * 2);  // TD size in bytes (2-byte entries)
  for (i = 0; i < tdx; i++) {
    Files_Write(&R, data[i] & 0xFF);
    Files_Write(&R, (data[i] >> 8) & 0xFF);
  }

  Files_WriteInt(&R, ORG_varsize - tdx * 2);
  Files_WriteInt(&R, strx);
  for (i = 0; i < strx; i++) {
	Files_Write(&R, str[i]);
  }
  
  Files_WriteInt(&R, ORG_pc - CODE_ORG);
  for (i = 0; i < ORG_pc - CODE_ORG; i++) {
	Files_Write(&R, code[i]);
  }
  
  obj = topScope->next;
  while (obj != NULL) {
	if ((obj->exno != 0) && (obj->class == ORB_Const) && 
		(obj->type->form == ORB_Proc) && (obj->type->nofpar == 0) && 
		(obj->type->base == noType)) {
	  Files_WriteString(&R, obj->name);
	  Files_WriteInt(&R, obj->val);
	}
	obj = obj->next;
  }
  Files_Write(&R, 0);
  
  Files_WriteInt(&R, nofent);
  Files_WriteInt(&R, entry);
  
  obj = topScope->next;
  while (obj != NULL) {
	if (obj->exno != 0) {
	  if (((obj->class == ORB_Const) && (obj->type->form == ORB_Proc)) ||
		  (obj->class == ORB_Var)) {
		Files_WriteInt(&R, obj->val);
	  } else if ((obj->class == ORB_Const) &&
				 (obj->type->form == ORB_Array || obj->type->form == ORB_Record)) {
		Files_WriteInt(&R, ORG_varsize + obj->val);  // offset from SB
	  } else if (obj->class == ORB_Typ) {
		if (obj->type->form == ORB_Record) {
		  Files_WriteInt(&R, obj->type->len % 0x10000);
		} else if ((obj->type->form == ORB_Pointer) && 
				   ((obj->type->base->typobj == NULL) || 
					(obj->type->base->typobj->exno == 0))) {
		  Files_WriteInt(&R, obj->type->base->len % 0x10000);
		}
	  }
	}
	obj = obj->next;
  }
  
  obj = topScope->next;
  while (obj != NULL) {
	if (obj->class == ORB_Var) {
	  FindPtrs(&R, obj->type, obj->val);
	}
	obj = obj->next;
  }
  
  Files_WriteInt(&R, -1);
  Files_WriteInt(&R, fixorgP);
  Files_WriteInt(&R, fixorgD);
  Files_WriteInt(&R, fixorgT);

  // Write TD fixup entries (ancestor addresses that need relocation)
  Files_WriteInt(&R, td_fixupC);
  for (i = 0; i < td_fixupC; i++) {
    Files_Write(&R, td_fixup[i][0] & 0xFF);         // byte offset lo
    Files_Write(&R, (td_fixup[i][0] >> 8) & 0xFF);  // byte offset hi
    Files_Write(&R, td_fixup[i][1] & 0xFF);          // mno lo
    Files_Write(&R, (td_fixup[i][1] >> 8) & 0xFF);   // mno hi
  }

  Files_WriteInt(&R, relocC);
  for (int i = 0; i < relocC; i++) {
	Files_WriteInt(&R, reloc[i]);
  }
  
  Files_WriteInt(&R, entry);
  Files_Write(&R, 'O');
  Files_Register(F);
}

// Module initialization
void ORG_Init(void) {
  relmap[0] = EQ;   // eql -> EQ
  relmap[1] = NE;   // neq -> NE  
  relmap[2] = LT;   // lss -> LT
  relmap[3] = GE;   // geq -> GE
  relmap[4] = LE;  // leq -> LE
  relmap[5] = GT;  // gtr -> GT
  longa = true; longi = true;
  relocC = 0;
}
