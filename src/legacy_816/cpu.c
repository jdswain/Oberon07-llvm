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

#include "cpu.h"
#include <stdio.h>

// Instruction name lookup table using the same DEF mechanism
static const char* instruction_names[] = {
#define DEF(tok, str, flags) str,
#include "../include/Instr.h"
#undef DEF
};

char *mode_to_string(enum AddrMode mode)
{
 switch( mode ) {
 case Absolute: return "Absolute";
 case Accumulator: return "Accumulator";
 case AbsoluteIndexedX: return "Absolute Indexed X";
 case AbsoluteIndexedY: return "Absolute Indexed Y";
 case AbsoluteLong: return "Absolute Long";
 case AbsoluteLongIndexedX: return "Absolute Long Indexed X";
 case AbsoluteIndirect: return "Absolute Indirect";
 case AbsoluteIndirectLong: return "Absolute Indirect Long";
 case AbsoluteIndexedIndirect: return "Absolute Indexed Indirect";
 case DirectPage: return "Direct Page";
 case StackDirectPageIndirect: return "Stack Direct Page Indirect";
 case DirectPageIndexedX: return "Direct Page Indexed X";
 case DirectPageIndexedY: return "Direct Page Indexed Y";
 case DirectPageIndirect: return "Direct Page Indirect";
 case DirectPageIndirectLong: return "Direct Page Indirect Long";
 case Implied: return "Implied";
 case ProgramCounterRelative: return "Program Counter Relative";
 case ProgramCounterRelativeLong: return "Program Counter Relative Long";
 case BlockMove: return "Block Move";
 case DirectPageIndexedIndirectX: return "Direct Page Indexed Indirect X";
 case DirectPageIndirectIndexedY: return "Direct Page Indirect Indexed Y";
 case DirectPageIndirectLongIndexedY: return "Direct Page Indirect Long Indexed Y";
 case Immediate: return "Immediate";
 case StackRelative: return "Stack Relative";
 case StackRelativeIndirectIndexedY: return "Stack Relative Indirect IndexedY";
 case Fixup: return "Fixup";
 }
 return "Invalid Mode";
}

const char* opcode_to_string(OpCode op) {
    if (op >= 0 && op < sizeof(instruction_names)/sizeof(instruction_names[0])) {
        return instruction_names[op];
    }
    return "UNKNOWN";
}

// 65C816 opcode to instruction mapping
// This maps actual 65C816 machine code bytes to our OpCode enum
OpCode byte_to_opcode(unsigned char byte) {
    switch (byte) {
        // Common 65C816 opcodes used by our compiler
        case 0x18: return sCLC;    // CLC - Clear Carry
        case 0x1A: return sINC;    // INC - Increment Accumulator  
        case 0x38: return sSEC;    // SEC - Set Carry
        case 0x3A: return sDEC;    // DEC - Decrement Accumulator
        case 0xFB: return sXCE;    // XCE - Exchange Carry and Emulation
        case 0xC2: return sREP;    // REP - Reset Status Bits
        case 0xE2: return sSEP;    // SEP - Set Status Bits
        
        // LDA variants
        case 0xA9: return sLDA;    // LDA Immediate
        case 0xA5: return sLDA;    // LDA Direct Page
        case 0xAD: return sLDA;    // LDA Absolute
        case 0xA7: return sLDA;    // LDA [Direct Page] (Direct Page Indirect Long)
        case 0xB7: return sLDA;    // LDA [Direct Page],Y (Direct Page Indirect Long Indexed Y)
        case 0xB1: return sLDA;    // LDA (Direct Page),Y (Direct Page Indirect Indexed Y)
        case 0xB2: return sLDA;    // LDA (Direct Page) (Direct Page Indirect)
        case 0xB5: return sLDA;    // LDA Direct Page,X
        case 0xBD: return sLDA;    // LDA Absolute,X
        case 0xB9: return sLDA;    // LDA Absolute,Y
        
        // STA variants
        case 0x85: return sSTA;    // STA Direct Page
        case 0x8D: return sSTA;    // STA Absolute
        case 0x87: return sSTA;    // STA [Direct Page] (Direct Page Indirect Long)
        case 0x92: return sSTA;    // STA Direct Page Indirect
        case 0x91: return sSTA;    // STA (Direct Page),Y (Direct Page Indirect Indexed Y)
        case 0x95: return sSTA;    // STA Direct Page,X
        case 0x9D: return sSTA;    // STA Absolute,X
        case 0x99: return sSTA;    // STA Absolute,Y
        
        // LDX variants
        case 0xA6: return sLDX;    // LDX Direct Page
        
        // AND variants
        case 0x29: return sAND;    // AND Immediate
        case 0x25: return sAND;    // AND Direct Page
        case 0x2D: return sAND;    // AND Absolute
        case 0x35: return sAND;    // AND Direct Page,X
        case 0x3D: return sAND;    // AND Absolute,X
        case 0x39: return sAND;    // AND Absolute,Y
        case 0x32: return sAND;    // AND (Direct Page)
        case 0x21: return sAND;    // AND (Direct Page,X)
        case 0x31: return sAND;    // AND (Direct Page),Y
        case 0x27: return sAND;    // AND [Direct Page]
        case 0x37: return sAND;    // AND [Direct Page],Y

        // ASL variants
        case 0x0A: return sASL;    // ASL Accumulator
        case 0x06: return sASL;    // ASL Direct Page
        case 0x0E: return sASL;    // ASL Absolute
        case 0x16: return sASL;    // ASL Direct Page,X
        case 0x1E: return sASL;    // ASL Absolute,X

        // EOR variants
        case 0x49: return sEOR;    // EOR Immediate
        case 0x45: return sEOR;    // EOR Direct Page
        case 0x4D: return sEOR;    // EOR Absolute
        case 0x55: return sEOR;    // EOR Direct Page,X
        case 0x5D: return sEOR;    // EOR Absolute,X
        case 0x59: return sEOR;    // EOR Absolute,Y
        case 0x52: return sEOR;    // EOR (Direct Page)
        case 0x41: return sEOR;    // EOR (Direct Page,X)
        case 0x51: return sEOR;    // EOR (Direct Page),Y
        case 0x47: return sEOR;    // EOR [Direct Page]
        case 0x57: return sEOR;    // EOR [Direct Page],Y

        // LSR variants
        case 0x4A: return sLSR;    // LSR Accumulator
        case 0x46: return sLSR;    // LSR Direct Page
        case 0x4E: return sLSR;    // LSR Absolute
        case 0x56: return sLSR;    // LSR Direct Page,X
        case 0x5E: return sLSR;    // LSR Absolute,X

        // ORA variants
        case 0x09: return sORA;    // ORA Immediate
        case 0x05: return sORA;    // ORA Direct Page
        case 0x0D: return sORA;    // ORA Absolute
        case 0x15: return sORA;    // ORA Direct Page,X
        case 0x1D: return sORA;    // ORA Absolute,X
        case 0x19: return sORA;    // ORA Absolute,Y
        case 0x12: return sORA;    // ORA (Direct Page)
        case 0x01: return sORA;    // ORA (Direct Page,X)
        case 0x11: return sORA;    // ORA (Direct Page),Y
        case 0x07: return sORA;    // ORA [Direct Page] (Direct Page Indirect Long)
        case 0x17: return sORA;    // ORA [Direct Page],Y

        // ROL variants
        case 0x2A: return sROL;    // ROL Accumulator
        case 0x26: return sROL;    // ROL Direct Page
        case 0x2E: return sROL;    // ROL Absolute
        case 0x36: return sROL;    // ROL Direct Page,X
        case 0x3E: return sROL;    // ROL Absolute,X
        
        // LDY variants
        case 0xA0: return sLDY;    // LDY Immediate
        case 0xA4: return sLDY;    // LDY Direct Page
        
        // ADC variants
        case 0x69: return sADC;    // ADC Immediate
        case 0x65: return sADC;    // ADC Direct Page
        case 0x6D: return sADC;    // ADC Absolute
        case 0x75: return sADC;    // ADC Direct Page,X
        case 0x7D: return sADC;    // ADC Absolute,X
        case 0x79: return sADC;    // ADC Absolute,Y
        
        // SBC variants
        case 0xE9: return sSBC;    // SBC Immediate
        case 0xE5: return sSBC;    // SBC Direct Page
        case 0xED: return sSBC;    // SBC Absolute
        case 0xF5: return sSBC;    // SBC Direct Page,X
        case 0xFD: return sSBC;    // SBC Absolute,X
        case 0xF9: return sSBC;    // SBC Absolute,Y
        
        // CMP variants
        case 0xC3: return sCMP;    // CMP Stack Relative
        case 0xC9: return sCMP;    // CMP Immediate
        case 0xC5: return sCMP;    // CMP Direct Page
        case 0xCD: return sCMP;    // CMP Absolute
        case 0xD5: return sCMP;    // CMP Direct Page,X
        case 0xDD: return sCMP;    // CMP Absolute,X
        case 0xD9: return sCMP;    // CMP Absolute,Y
        
        // Branch instructions
        case 0x10: return sBPL;    // BPL - Branch if Plus
        case 0x30: return sBMI;    // BMI - Branch if Minus
        case 0x50: return sBVC;    // BVC - Branch if Overflow Clear
        case 0x70: return sBVS;    // BVS - Branch if Overflow Set
        case 0x90: return sBCC;    // BCC - Branch if Carry Clear
        case 0xB0: return sBCS;    // BCS - Branch if Carry Set
        case 0xD0: return sBNE;    // BNE - Branch if Not Equal
        case 0xF0: return sBEQ;    // BEQ - Branch if Equal
        case 0x80: return sBRA;    // BRA - Branch Always
        case 0x82: return sBRL;    // BRL - Branch Long Always
        
        // Index register increment/decrement
        case 0xC8: return sINY;    // INY - Increment Y
        case 0xE8: return sINX;    // INX - Increment X
        
        // Transfer instructions
        case 0xAA: return sTAX;    // TAX - Transfer A to X
        case 0xA8: return sTAY;    // TAY - Transfer A to Y
        case 0x8A: return sTXA;    // TXA - Transfer X to A
        case 0x98: return sTYA;    // TYA - Transfer Y to A
        
        // Other common instructions
        case 0x20: return sJSR;    // JSR Absolute
        case 0x22: return sJSL;    // JSL Absolute Long
        case 0xEA: return sNOP;    // NOP
        case 0x00: return sBRK;    // BRK
        case 0x40: return sRTI;    // RTI
        case 0x60: return sRTS;    // RTS
        case 0x6B: return sRTL;    // RTL
        
        // Stack operations
        case 0x3B: return sTSC;    // TSC - Transfer Stack Pointer to A
        case 0x1B: return sTCS;    // TCS - Transfer A to Stack Pointer
        case 0xFA: return sPLX;    // PLX - Pull X from Stack
        case 0xDA: return sPHX;    // PHX - Push X to Stack
        
        // Stack relative addressing
        case 0xA3: return sLDA;    // LDA sr,S (Stack Relative)
        case 0x83: return sSTA;    // STA sr,S (Stack Relative)
        
        // Stack relative indirect indexed Y addressing
        case 0xB3: return sLDA;    // LDA (sr,S),Y (Stack Relative Indirect Indexed Y)
        case 0x93: return sSTA;    // STA (sr,S),Y (Stack Relative Indirect Indexed Y)
        
        default: return sNOP;      // Unknown opcode, treat as NOP for safety
    }
}

