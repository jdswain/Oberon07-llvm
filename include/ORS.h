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

// ORS.h - Oberon Scanner (Lexical Analyzer) Header

#ifndef ORS_H
#define ORS_H

#include "Oberon.h"
#include "Texts.h"

// Constants
#define ORS_IDENT_LEN 32
#define ORS_STRING_LEN 256

// Symbol constants (tokens)
typedef enum {
    ORS_null = 0,
    ORS_times = 1, ORS_rdiv = 2, ORS_div = 3, ORS_mod = 4,
    ORS_and = 5, ORS_plus = 6, ORS_minus = 7, ORS_or = 8,
    ORS_eql = 9, ORS_neq = 10, ORS_lss = 11, ORS_geq = 12,
    ORS_leq = 13, ORS_gtr = 14, ORS_in = 15, ORS_is = 16,
    ORS_arrow = 17, ORS_period = 18,
    ORS_char = 20, ORS_int = 21, ORS_real = 22, ORS_false = 23, ORS_true = 24,
    ORS_nil = 25, ORS_string = 26, ORS_not = 27, ORS_lparen = 28, ORS_lbrak = 29,
    ORS_lbrace = 30, ORS_ident = 31,
    ORS_if = 32, ORS_while = 34, ORS_repeat = 35, ORS_case = 36, ORS_for = 37,
    ORS_comma = 40, ORS_colon = 41, ORS_becomes = 42, ORS_upto = 43, ORS_rparen = 44,
    ORS_rbrak = 45, ORS_rbrace = 46, ORS_then = 47, ORS_of = 48, ORS_do = 49,
    ORS_to = 50, ORS_by = 51, ORS_semicolon = 52, ORS_end = 53, ORS_bar = 54,
    ORS_else = 55, ORS_elsif = 56, ORS_until = 57, ORS_return = 58,
    ORS_array = 60, ORS_record = 61, ORS_pointer = 62, ORS_const = 63, ORS_type = 64,
    ORS_var = 65, ORS_procedure = 66, ORS_begin = 67, ORS_import = 68, ORS_module = 69,
    ORS_eof = 70,
    /* ORS_weak placed *after* eof so it falls outside the existing
       "type-token" / "decl-token" ranges in ORP. The parser tests for
       ORS_weak by equality before falling into the regular pointer-type
       branch. Inserting it inside the type-token range would have shifted
       every later token's numeric value and forced ranged-test rewrites. */
    ORS_weak = 71
} ORS_Symbol;

// Type definitions
typedef char ORS_Ident[ORS_IDENT_LEN];

// Global variables (exported from ORS module)
extern ORS_Ident ORS_id;           // Current identifier
extern LONGINT ORS_ival;           // Current integer value
extern REAL ORS_rval;              // Current real value
extern LONGINT ORS_slen;           // Current string length
extern char ORS_str[ORS_STRING_LEN]; // Current string value
extern INTEGER ORS_errcnt;         // Error count

// Scanner functions
void ORS_Mark(char *msg);
void ORS_Get(INTEGER *sym);
LONGINT ORS_Pos(void);
void ORS_Init(Texts_Text *T, LONGINT pos);

// Utility functions
void ORS_CopyId(ORS_Ident dest);

#endif // ORS_H
