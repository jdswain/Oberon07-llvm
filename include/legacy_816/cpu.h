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

#ifndef CPU_H
#define CPU_H

// Symbols
typedef enum {
#define DEF(tok, str, flags) s ## tok,
#include "Instr.h"
#undef DEF
#undef TOK
} OpCode;


enum AddrMode {
  Absolute,                      /* addr */
  Accumulator,                   /* A */
  AbsoluteIndexedX,              /* addr,X */
  AbsoluteIndexedY,              /* addr,Y */
  AbsoluteLong,                  /* long */
  AbsoluteLongIndexedX,          /* long,X */
  AbsoluteIndirect,              /* (addr) */
  AbsoluteIndexedIndirect,       /* (addr,X) */
  DirectPage,                    /* dp*/
  StackDirectPageIndirect,       /* dp,s */
  DirectPageIndexedX,            /* dp,X */
  DirectPageIndexedY,            /* dp,Y */
  DirectPageIndirect,            /* (dp) */
  DirectPageIndirectLong,        /* [dp] */
  Implied,                       /* */
  /* Stack, */
  ProgramCounterRelative,        /* nearlabel */
  ProgramCounterRelativeLong,    /* label */
  Fixup,                         /* forward branch fixup */
  AbsoluteIndirectLong,          /* [addr] */
  BlockMove,                     /* srcbk,destbk */
  DirectPageIndexedIndirectX,    /* (dp,X) */
  DirectPageIndirectIndexedY,    /* (dp),Y */
  DirectPageIndirectLongIndexedY,/* [dp],Y */
  Immediate,                     /* #const */
  //StackProgramCounterRelative,   /* label */
  StackRelative,                 /* sr,S d,s */
  StackRelativeIndirectIndexedY, /* (sr,S),Y */
};
typedef enum AddrMode AddrMode;

enum Modifier {
  MByte,
  MDirect,
  MAbsolute,
  MWord,
  MLong,
  MFloat,
  MDouble,
  MZero,
  MBit7,
  MNone
};
typedef enum Modifier Modifier;

char *mode_to_string(enum AddrMode mode);
const char* opcode_to_string(OpCode op);
OpCode byte_to_opcode(unsigned char byte);

#endif
