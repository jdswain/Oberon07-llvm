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

#ifndef CODEGEN_H
#define CODEGEN_H

#include <stdbool.h>
#include <stdint.h>

#include "cpu.h"

extern bool longa;
extern bool longi;

#define maxReloc 1024

extern int relocC;
extern int reloc[maxReloc];

void codegen_gen(OpCode opcode, AddrMode mode, int value1, int value2);
void codegen_byte(int b);
void codegen_word(int w);
void codegen_long(int l);

// Internal code generation functions
void or(uint8_t op, int v);   // Relative branch with calculated offset
void of(uint8_t op, int v);   // Fixup branch with chain link

/* Used for formatting the addressing mode for the listing */
char *codegen_format_mode(AddrMode mode, int value1, int value2);
char *codegen_format_mode_str(AddrMode mode, char *value1, int value2);

#endif
