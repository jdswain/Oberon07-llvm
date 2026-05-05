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

#include "codegen.h"

#include <stdio.h>
#include "ORG.h"

#define CODE_ORG 0x0000  // Code starts at $0000

bool longa = true;
bool longi = true;
int dpage = 0;
int pbreg = 0;

int relocC;
int reloc[maxReloc];

void o(uint8_t byte)
{
  code[ORG_pc - CODE_ORG] = byte;
  ORG_pc++;
}

/* Standard formats */

void ob(uint8_t op, int v)
{
  if (v > 255 || v < 0) {
    fprintf(stderr, "Warning: 8-bit operand overflow: %d (0x%x) at PC $%04X\n", v, v, ORG_pc);
  }
  o(op); o(v & 0xff);
}

void odp(uint8_t op, int v)
{
  ob(op, v);
}

void ow(uint8_t op, int v)
{
  o(op); o(v & 0xff); o(v >> 8);
}

void oabs(uint8_t op, int v)
{
  ow(op, v);
}

void ol(uint8_t op, int v)
{
  o(op); o(v & 0xff); o(v >> 8); o(v >> 16);
}

void olong(uint8_t op, int v)
{
  ol(op, v);
}

void om(uint8_t op, int v, bool b) { o(op); o(v & 0xff); if( b ) o(v >> 8); }

void or(uint8_t op, int v) {
  o(op);
  int r = v - (ORG_pc + 1);
  o(r & 0xff);
}

void of(uint8_t op, int v) {
  // Fixup branch: store opcode and fixup chain link
  if (v == 0) {
    // First forward branch in chain
    ow(op, 0);
  } else {
    // Forward branch - store relative offset to previous branch in chain
    // v is the address of the previous offset byte
    // ORG_pc now points to current offset byte location (after emitting opcode)
    int chain_offset = v - ORG_pc;
    ow(op, chain_offset & 0xff);
  }
}

void ofl(uint8_t op, int v) {
  // Fixup branch: store opcode and fixup chain link (absolute address)
  // For BRL fixup chains, we store the absolute address of the next chain link
  ow(op, v & 0xffff);
}

/* 65C816 formats */

void orl(uint8_t op, int v) {
  o(op);
  int r = v - (ORG_pc + 2);
  o(r & 0xff); o(r >> 8);
}

void omove(uint8_t op, int src, int dst) { o(op); o(dst >> 16); o(src >> 16); }

void codegen_byte(int b) { o(b & 0xff); }
void codegen_word(int w) { o(w & 0xff); o(w >> 8); }
void codegen_long(int l) { o(l & 0xff); o(l >> 8 & 0xff); o(l >> 16 & 0xff); o(l >> 24 & 0xff); }

#include "gen_816.c"

int codegen_params(AddrMode mode)
{
  switch (mode) {
  case Absolute: return 1;
  case Accumulator: return 0;
  case AbsoluteIndexedX: return 1;
  case AbsoluteIndexedY: return 1;
  case AbsoluteLong: return 1;
  case AbsoluteLongIndexedX: return 1;
  case AbsoluteIndirect: return 1;
  case AbsoluteIndirectLong: return 1;
  case AbsoluteIndexedIndirect: return 1;
  case DirectPage: return 1;
  case StackDirectPageIndirect: return 1;
  case DirectPageIndexedX: return 1;
  case DirectPageIndexedY: return 1;
  case DirectPageIndirect: return 1;
  case DirectPageIndirectLong: return 1;
  case Implied: return 0;
  case ProgramCounterRelative: return 1;
  case ProgramCounterRelativeLong: return 1;
  case BlockMove: return 2;
  case DirectPageIndexedIndirectX: return 1;
  case DirectPageIndirectIndexedY: return 1;
  case DirectPageIndirectLongIndexedY: return 1;
  case Immediate: return 1;
  case StackRelative: return 1;
  case StackRelativeIndirectIndexedY: return 1;
  case Fixup: return 1;
  }
  return 0;
}

bool is_dp(int addr)
{
  return (addr < 0x100) || ((addr - dpage) < 0x100);
}

bool is_long_program(int addr)
{ 
  return (addr > 0xffff) || ((addr - pbreg) < 0x10000);
}

bool is_long_data(int addr)
{
  return (addr > 0xffff); 
}

void codegen_gen(OpCode opcode, AddrMode mode, int value1, int value2)
{
  
  // Optimisations
  if (mode == Absolute) {
    if (is_dp(value1)) mode = DirectPage;
  }
  //  else if (mode == AbsoluteIndexedX) {
  //    if (is_dp(value1)) mode = DirectPageIndexedX;
  //  }
  else if (mode == AbsoluteIndexedY) {
    if (is_dp(value1)) mode = DirectPageIndexedY;
  }
  else if (mode == AbsoluteIndexedIndirect) {
    if (is_dp(value1)) mode = DirectPageIndexedIndirectX;
  }
  else if (mode == AbsoluteIndirect) {
    if (is_long_data(value1)) mode = AbsoluteIndirectLong;
    else if (is_dp(value1)) mode = AbsoluteIndirect;
  }

  gen_816(opcode, mode, value1, value2);
}

char buffer[24];

char *codegen_format_mode(AddrMode mode, int value1, int value2)
{
  /* ToDo: modifer for value length is not implemented here, assuming 65C816 native mode */
  switch (mode) {
  case Absolute: sprintf(buffer, "$%04x", value1); break;
  case Accumulator: sprintf(buffer, "A"); break;
  case AbsoluteIndexedX: sprintf(buffer, "$%04x,X", value1); break;
  case AbsoluteIndexedY: sprintf(buffer, "$%04x,Y", value1); break;
  case AbsoluteLong: sprintf(buffer, "$%06x", value1); break;
  case AbsoluteLongIndexedX: sprintf(buffer, "$%06x,X", value1); break;
  case AbsoluteIndirect: sprintf(buffer, "($%04x)", value1); break;
  case AbsoluteIndexedIndirect: sprintf(buffer, "($%04x,X)", value1); break;
  case DirectPage: sprintf(buffer, "$%02x", value1); break;
  case StackDirectPageIndirect: sprintf(buffer, "$%02x,s", value1); break;
  case DirectPageIndexedX: sprintf(buffer, "$%02x,X", value1); break;
  case DirectPageIndexedY: sprintf(buffer, "$%02x,Y", value1); break;
  case DirectPageIndirectLongIndexedY: sprintf(buffer, "[$%02x],Y", value1); break;
  case DirectPageIndirect: sprintf(buffer, "($%02x)", value1); break;
  case DirectPageIndirectLong: sprintf(buffer, "[$%02x]", value1); break;
  case Implied: buffer[0] = 0; break;
  /* Stack, */
  case ProgramCounterRelative: sprintf(buffer, "$%02x", value1); break;
  case ProgramCounterRelativeLong: sprintf(buffer, "$%04x", value1); break;
  case Fixup: sprintf(buffer, "*%02x", value1); break;
  case AbsoluteIndirectLong: sprintf(buffer, "[$%04x]", value1); break;
  case BlockMove: sprintf(buffer, "$%02x,$%02x", value1, value2); break;
  case DirectPageIndexedIndirectX: sprintf(buffer, "($%02x,X)", value1); break;
  case DirectPageIndirectIndexedY: sprintf(buffer, "($%02x),Y", value1); break;
  case Immediate: sprintf(buffer, "#$%04x", value1); break;
  case StackRelative: sprintf(buffer, "#$%02x,S", value1); break;
  case StackRelativeIndirectIndexedY: sprintf(buffer, "(#$%02x,S),Y", value1); break;
  }

  return (char *)&buffer;
}

char *codegen_format_mode_str(AddrMode mode, char *value1, int value2)
{
  /* ToDo: modifer for value length is not implemented here, assuming 65C816 native mode */
  switch (mode) {
  case Absolute: sprintf(buffer, "%s", value1); break;
  case Accumulator: sprintf(buffer, "A"); break;
  case AbsoluteIndexedX: sprintf(buffer, "%s,X", value1); break;
  case AbsoluteIndexedY: sprintf(buffer, "%s,Y", value1); break;
  case AbsoluteLong: sprintf(buffer, "%s", value1); break;
  case AbsoluteLongIndexedX: sprintf(buffer, "%s,X", value1); break;
  case AbsoluteIndirect: sprintf(buffer, "(%s)", value1); break;
  case AbsoluteIndexedIndirect: sprintf(buffer, "(%s,X)", value1); break;
  case DirectPage: sprintf(buffer, "%s", value1); break;
  case StackDirectPageIndirect: sprintf(buffer, "%s,s", value1); break;
  case DirectPageIndexedX: sprintf(buffer, "%s,X", value1); break;
  case DirectPageIndexedY: sprintf(buffer, "%s,Y", value1); break;
  case DirectPageIndirectLongIndexedY: sprintf(buffer, "[%s],Y", value1); break;
  case DirectPageIndirect: sprintf(buffer, "(%s)", value1); break;
  case DirectPageIndirectLong: sprintf(buffer, "[%s]", value1); break;
  case Implied: buffer[0] = 0; break;
  /* Stack, */
  case ProgramCounterRelative: sprintf(buffer, "%s", value1); break;
  case ProgramCounterRelativeLong: sprintf(buffer, "%s", value1); break;
  case Fixup: sprintf(buffer, "*%s", value1); break;
  case AbsoluteIndirectLong: sprintf(buffer, "[%s]", value1); break;
  case BlockMove: sprintf(buffer, "%s,$%02x", value1, value2); break;
  case DirectPageIndexedIndirectX: sprintf(buffer, "(%s,X)", value1); break;
  case DirectPageIndirectIndexedY: sprintf(buffer, "(%s),Y", value1); break;
  case Immediate: sprintf(buffer, "#%s", value1); break;
  case StackRelative: sprintf(buffer, "#%s,S", value1); break;
  case StackRelativeIndirectIndexedY: sprintf(buffer, "(#%s,S),Y", value1); break;
  }
  return (char *)&buffer;
}
