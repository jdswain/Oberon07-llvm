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

// Files.c - File system implementation

#include "Files.h"
#include <stdlib.h>
#include <string.h>

// Open existing file
Files_File* Files_Old(char *name) {
    Files_File *f;
    FILE *fp;
    
    fp = fopen(name, "rb");
    if (!fp) return NULL;
    
    f = (Files_File*)malloc(sizeof(Files_File));
    if (!f) {
        fclose(fp);
        return NULL;
    }
    
    f->fp = fp;
    f->name = (char*)malloc(strlen(name) + 1);
    strcpy(f->name, name);
    
    // Get file length
    fseek(fp, 0, SEEK_END);
    f->length = ftell(fp);
    fseek(fp, 0, SEEK_SET);
    
    f->modified = FALSE;
    f->buffer = NULL;
    f->buflen = 0;
    f->bufcap = 0;
    return f;
}

// Create new file
Files_File* Files_New(char *name) {
    Files_File *f;
    
    f = (Files_File*)malloc(sizeof(Files_File));
    if (!f) return NULL;
    
    f->fp = NULL;  // Will be opened when registered
    f->name = (char*)malloc(strlen(name) + 1);
    strcpy(f->name, name);
    f->length = 0;
    f->modified = TRUE;
    
    // Initialize buffer for writing
    f->bufcap = 1024;  // Start with 1KB buffer
    f->buffer = (char*)malloc(f->bufcap);
    f->buflen = 0;
    
    if (!f->buffer) {
        free(f->name);
        free(f);
        return NULL;
    }
    
    return f;
}

// Open existing file for read/write
Files_File* Files_Update(char *name) {
    Files_File *f;
    FILE *fp;
    
    fp = fopen(name, "r+b");  // Open for read/write
    if (!fp) return NULL;
    
    f = (Files_File*)malloc(sizeof(Files_File));
    if (!f) {
        fclose(fp);
        return NULL;
    }
    
    f->fp = fp;
    f->name = (char*)malloc(strlen(name) + 1);
    strcpy(f->name, name);
    
    // Get file length
    fseek(fp, 0, SEEK_END);
    f->length = ftell(fp);
    fseek(fp, 0, SEEK_SET);
    
    f->modified = FALSE;
    f->buffer = NULL;
    f->buflen = 0;
    f->bufcap = 0;
    return f;
}

// Register (save) file
void Files_Register(Files_File *f) {
    if (f && f->modified) {
        if (!f->fp) {
            f->fp = fopen(f->name, "wb");
        }
        if (f->fp) {
            // Write buffer to disk if it exists
            if (f->buffer && f->buflen > 0) {
                fwrite(f->buffer, 1, f->buflen, f->fp);
            }
            fflush(f->fp);
            f->modified = FALSE;
        }
    }
}

// Close file
void Files_Close(Files_File *f) {
    if (f) {
        if (f->fp) fclose(f->fp);
        if (f->name) free(f->name);
        if (f->buffer) free(f->buffer);
        free(f);
    }
}

// Get file length
LONGINT Files_Length(Files_File *f) {
    return f ? f->length : 0;
}

// Set rider position
void Files_Set(Files_Rider *r, Files_File *f, LONGINT pos) {
    if (r) {
        r->file = f;
        r->pos = pos;
        r->eof = FALSE;
        if (f && f->fp) {
            fseek(f->fp, pos, SEEK_SET);
        }
        // For buffered files, ensure buffer can accommodate the position
        if (f && f->buffer && pos > f->buflen) {
            // Don't seek beyond current buffer length for new files
            r->pos = f->buflen;
        }
    }
}

// Get rider position
LONGINT Files_Pos(Files_Rider *r) {
    return r ? r->pos : 0;
}

// Read character
void Files_Read(Files_Rider *r, char *x) {
    if (r && r->file && !r->eof) {
        if (r->file->fp) {
            // Read from existing file
            int c = fgetc(r->file->fp);
            if (c == EOF) {
                r->eof = TRUE;
                *x = 0;
            } else {
                *x = (char)c;
                r->pos++;
            }
        } else if (r->file->buffer) {
            // Read from buffer for new file
            if (r->pos >= r->file->buflen) {
                r->eof = TRUE;
                *x = 0;
            } else {
                *x = r->file->buffer[r->pos];
                r->pos++;
            }
        } else {
            *x = 0;
        }
    } else {
        *x = 0;
    }
}

// Read byte
void Files_ReadByte(Files_Rider *r, BYTE *x) {
    char c;
    Files_Read(r, &c);
    *x = (BYTE)c;
}

// Read integer  
void Files_ReadInt(Files_Rider *r, LONGINT *x) {
    BYTE b0 = 0, b1 = 0, b2 = 0, b3 = 0;
    
    Files_ReadByte(r, &b0);
    if (r->eof) { *x = 0; return; }
    
    Files_ReadByte(r, &b1);
    if (r->eof) { *x = b0; return; }
    
    Files_ReadByte(r, &b2);
    if (r->eof) { *x = b0 | (b1 << 8); return; }
    
    Files_ReadByte(r, &b3);
    *x = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
}

// Read long integer
void Files_ReadLInt(Files_Rider *r, LONGINT *x) {
    BYTE b0 = 0, b1 = 0, b2 = 0, b3 = 0;
    
    Files_ReadByte(r, &b0);
    if (r->eof) { *x = 0; return; }
    
    Files_ReadByte(r, &b1);
    if (r->eof) { *x = b0; return; }
    
    Files_ReadByte(r, &b2);
    if (r->eof) { *x = b0 | (b1 << 8); return; }
    
    Files_ReadByte(r, &b3);
    *x = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
}

// Read real number
void Files_ReadReal(Files_Rider *r, REAL *x) {
    Files_ReadLInt(r, (LONGINT*)x);
}

// Read string
void Files_ReadString(Files_Rider *r, char *x) {
    char ch;
    INTEGER i = 0;
    
    do {
        Files_Read(r, &ch);
        x[i] = ch;
        i++;
    } while (ch != 0 && i < 255);
    
    if (i >= 255) {
        x[254] = 0;  // Ensure null termination
    }
}

// Read number (variable length encoding)
void Files_ReadNum(Files_Rider *r, LONGINT *x) {
    BYTE b;
    LONGINT n = 0;
    LONGINT shift = 0;
    
    do {
        Files_ReadByte(r, &b);
        if (r->eof) {
            *x = n;  // Return partial result if EOF encountered
            return;
        }
        n |= ((LONGINT)(b & 0x7F)) << shift;
        shift += 7;
    } while ((b & 0x80) != 0);
    
    // Handle sign extension
    if ((b & 0x40) != 0) {
        n |= -(1L << shift);
    }
    
    *x = n;
}

// Write character
void Files_Write(Files_Rider *r, char x) {
    if (r && r->file) {
        if (r->file->fp) {
            // Write to existing file
            fputc(x, r->file->fp);
            r->pos++;
            r->file->modified = TRUE;
            if (r->pos > r->file->length) {
                r->file->length = r->pos;
            }
        } else if (r->file->buffer) {
            // Write to buffer for new file
            // Expand buffer if needed
            if (r->pos >= r->file->bufcap) {
                LONGINT newcap = r->file->bufcap * 2;
                char *newbuf = (char*)realloc(r->file->buffer, newcap);
                if (newbuf) {
                    r->file->buffer = newbuf;
                    r->file->bufcap = newcap;
                } else {
                    return;  // Failed to expand buffer
                }
            }
            
            r->file->buffer[r->pos] = x;
            r->pos++;
            r->file->modified = TRUE;
            
            // Update buffer length and file length
            if (r->pos > r->file->buflen) {
                r->file->buflen = r->pos;
            }
            if (r->pos > r->file->length) {
                r->file->length = r->pos;
            }
        }
    }
}

// Write byte
void Files_WriteByte(Files_Rider *r, BYTE x) {
    Files_Write(r, (char)x);
}

// Write integer
void Files_WriteInt(Files_Rider *r, LONGINT x) {
    Files_WriteByte(r, x & 0xFF);
    Files_WriteByte(r, (x >> 8) & 0xFF);
    Files_WriteByte(r, (x >> 16) & 0xFF);
    Files_WriteByte(r, (x >> 24) & 0xFF);
}

// Write long integer
void Files_WriteLInt(Files_Rider *r, LONGINT x) {
    Files_WriteByte(r, x & 0xFF);
    Files_WriteByte(r, (x >> 8) & 0xFF);
    Files_WriteByte(r, (x >> 16) & 0xFF);
    Files_WriteByte(r, (x >> 24) & 0xFF);
}

// Write real number
void Files_WriteReal(Files_Rider *r, REAL x) {
    Files_WriteLInt(r, *(LONGINT*)&x);
}

// Write string
void Files_WriteString(Files_Rider *r, const char *x) {
    INTEGER i = 0;
    while (x[i] != 0) {
        Files_Write(r, x[i]);
        i++;
    }
    Files_Write(r, 0);  // Null terminator
}

// Write number (variable length encoding)
void Files_WriteNum(Files_Rider *r, LONGINT x) {
    while (x < -64 || x >= 64) {
        Files_WriteByte(r, (x & 0x7F) | 0x80);
        x >>= 7;
    }
    Files_WriteByte(r, x & 0x7F);
}
