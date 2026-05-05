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

// Oberon.h - Common type definitions for Oberon compiler
// Maps Oberon basic types to C types

#ifndef OBERON_H
#define OBERON_H

#include <stdint.h>

// Basic Oberon types mapped to C types
typedef uint8_t BYTE;
typedef int16_t INTEGER;
typedef int32_t LONGINT;
typedef float REAL;
typedef double LONGREAL;
typedef int BOOLEAN;
typedef char CHAR;
typedef uint32_t SET;

// Boolean constants
#ifndef TRUE
#define TRUE 1
#endif

#ifndef FALSE
#define FALSE 0
#endif

// Character constants
#define CHR(x) ((CHAR)(x))
#define ORD(x) ((INTEGER)(x))

// Set operations
#define INCL(s, x) ((s) |= (1U << (x)))
#define EXCL(s, x) ((s) &= ~(1U << (x)))
#define IN(x, s) (((s) & (1U << (x))) != 0)

// Common string type for identifiers
#define IDENT_LEN 32
typedef char Ident[IDENT_LEN];

// Memory allocation helpers
#define NEW(ptr, type) ((ptr) = (type*)malloc(sizeof(type)))
#define DISPOSE(ptr) free(ptr)

// NIL pointer
#ifndef NULL
#define NULL ((void*)0)
#endif
#define NIL NULL

// Array length helper
#define LEN(arr) (sizeof(arr)/sizeof((arr)[0]))

// Min/Max helpers
#define MIN(a, b) ((a) < (b) ? (a) : (b))
#define MAX(a, b) ((a) > (b) ? (a) : (b))

// Abs helper
#define ABS(x) ((x) < 0 ? -(x) : (x))

// ODD helper
#define ODD(x) ((x) & 1)

#endif // OBERON_H
