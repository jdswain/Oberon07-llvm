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

// Texts.h - Text module interface for Oberon compiler

#ifndef TEXTS_H
#define TEXTS_H

#include "Oberon.h"
#include <stdio.h>

// Constants
#define MAX_TEXT_LEN 65536
#define MAX_SCANNER_STRING 256

// Text classes for scanner
typedef enum {
    Texts_Inval = 0,
    Texts_Name = 1,
    Texts_String = 2,
    Texts_Int = 3,
    Texts_Real = 4,
    Texts_Char = 5,
    Texts_End = 6
} Texts_Class;

// Forward declarations
typedef struct Texts_Text Texts_Text;
typedef struct Texts_Writer Texts_Writer;
typedef struct Texts_Scanner Texts_Scanner;

// Text structure
struct Texts_Text {
    char *data;
    LONGINT len;
    LONGINT maxlen;
};

// Writer structure
struct Texts_Writer {
    char *buf;
    LONGINT pos;
    LONGINT maxlen;
};

// Scanner structure
struct Texts_Scanner {
    Texts_Text *text;
    LONGINT pos;
    Texts_Class class;
    char c;
    char nextCh;
    char s[MAX_SCANNER_STRING];
    LONGINT i;
    REAL x;
};

// Text operations
void Texts_Open(Texts_Text *T, char *name);
void Texts_Close(Texts_Text *T);
LONGINT Texts_Length(Texts_Text *T);
void Texts_Read(Texts_Text *T, LONGINT pos, char *ch);
void Texts_Write(Texts_Text *T, LONGINT pos, char ch);
void Texts_Insert(Texts_Text *T, LONGINT pos, char *src, LONGINT len);
void Texts_Delete(Texts_Text *T, LONGINT beg, LONGINT end);
void Texts_Append(Texts_Text *T, char *buf);

// Writer operations
void Texts_OpenWriter(Texts_Writer *W);
void Texts_ClearWriter(Texts_Writer *W);
void Texts_WriteChar(Texts_Writer *W, char ch);
void Texts_WriteString(Texts_Writer *W, char *s);
void Texts_WriteInt(Texts_Writer *W, LONGINT x, LONGINT n);
void Texts_WriteHex(Texts_Writer *W, LONGINT x);
void Texts_WriteLn(Texts_Writer *W);

// Scanner operations
void Texts_OpenScanner(Texts_Scanner *S, Texts_Text *T, LONGINT pos);
void Texts_Scan(Texts_Scanner *S);

// Global log text (simplified)
extern Texts_Text *Oberon_Log;

// Parameter structure (simplified)
typedef struct {
    Texts_Text *text;
    LONGINT pos;
} Oberon_Par_Struct;

extern Oberon_Par_Struct Oberon_Par;

// Selection operations (simplified)
void Oberon_GetSelection(Texts_Text **T, LONGINT *beg, LONGINT *end, LONGINT *time);
void Oberon_Collect(LONGINT option);

#endif // TEXTS_H
