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

// Files.h - File system interface for Oberon compiler

#ifndef FILES_H
#define FILES_H

#include "Oberon.h"
#include <stdio.h>

// Forward declarations
typedef struct Files_File Files_File;
typedef struct Files_Rider Files_Rider;

// File structure
struct Files_File {
    FILE *fp;
    char *name;
    LONGINT length;
    BOOLEAN modified;
    char *buffer;     // Memory buffer for new files
    LONGINT buflen;   // Current buffer length
    LONGINT bufcap;   // Buffer capacity
};

// Rider structure (file position marker)
struct Files_Rider {
    Files_File *file;
    LONGINT pos;
    BOOLEAN eof;
};

// File operations
Files_File* Files_Old(char *name);
Files_File* Files_New(char *name);
Files_File* Files_Update(char *name);  // Open existing file for read/write
void Files_Register(Files_File *f);
void Files_Close(Files_File *f);
LONGINT Files_Length(Files_File *f);

// Rider operations
void Files_Set(Files_Rider *r, Files_File *f, LONGINT pos);
LONGINT Files_Pos(Files_Rider *r);

// Reading operations
void Files_Read(Files_Rider *r, char *x);
void Files_ReadByte(Files_Rider *r, BYTE *x);
void Files_ReadInt(Files_Rider *r, LONGINT *x);
void Files_ReadLInt(Files_Rider *r, LONGINT *x);
void Files_ReadReal(Files_Rider *r, REAL *x);
void Files_ReadString(Files_Rider *r, char *x);
void Files_ReadNum(Files_Rider *r, LONGINT *x);

// Writing operations
void Files_Write(Files_Rider *r, char x);
void Files_WriteByte(Files_Rider *r, BYTE x);
void Files_WriteInt(Files_Rider *r, LONGINT x);
void Files_WriteLInt(Files_Rider *r, LONGINT x);
void Files_WriteReal(Files_Rider *r, REAL x);
void Files_WriteString(Files_Rider *r, const char *x);
void Files_WriteNum(Files_Rider *r, LONGINT x);

#endif // FILES_H
