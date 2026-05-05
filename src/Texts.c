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

// Texts.c - Text module implementation for Oberon compiler

#include "Texts.h"
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

// Global variables
static Texts_Text log_text;
Texts_Text *Oberon_Log = &log_text;
Oberon_Par_Struct Oberon_Par = {NULL, 0};

// Initialize the log text
static void init_log(void) {
    static BOOLEAN initialized = FALSE;
    if (!initialized) {
        log_text.data = (char*)malloc(MAX_TEXT_LEN);
        log_text.len = 0;
        log_text.maxlen = MAX_TEXT_LEN;
        if (log_text.data) {
            log_text.data[0] = '\0';
        }
        initialized = TRUE;
    }
}

// Text operations
void Texts_Open(Texts_Text *T, char *name) {
    FILE *f;
    
    T->data = (char*)malloc(MAX_TEXT_LEN);
    T->maxlen = MAX_TEXT_LEN;
    T->len = 0;
    
    if (!T->data) return;
    
    f = fopen(name, "r");
    if (f) {
        T->len = fread(T->data, 1, MAX_TEXT_LEN - 1, f);
        T->data[T->len] = '\0';
        fclose(f);
    } else {
        T->len = 0;
        T->data[0] = '\0';
    }
}

void Texts_Close(Texts_Text *T) {
    if (T && T->data) {
        free(T->data);
        T->data = NULL;
        T->len = 0;
        T->maxlen = 0;
    }
}

LONGINT Texts_Length(Texts_Text *T) {
    return T ? T->len : 0;
}

void Texts_Read(Texts_Text *T, LONGINT pos, char *ch) {
    if (T && T->data && pos >= 0 && pos < T->len) {
        *ch = T->data[pos];
    } else {
        *ch = '\0';
    }
}

void Texts_Write(Texts_Text *T, LONGINT pos, char ch) {
    if (T && T->data && pos >= 0 && pos < T->maxlen) {
        T->data[pos] = ch;
        if (pos >= T->len) {
            T->len = pos + 1;
            if (T->len < T->maxlen) {
                T->data[T->len] = '\0';
            }
        }
    }
}

void Texts_Insert(Texts_Text *T, LONGINT pos, char *src, LONGINT len) {
    if (!T || !T->data || !src || len <= 0) return;
    if (pos < 0) pos = 0;
    if (pos > T->len) pos = T->len;
    
    if (T->len + len >= T->maxlen) {
        len = T->maxlen - T->len - 1;
        if (len <= 0) return;
    }
    
    // Move existing text
    memmove(T->data + pos + len, T->data + pos, T->len - pos);
    // Insert new text
    memcpy(T->data + pos, src, len);
    T->len += len;
    T->data[T->len] = '\0';
}

void Texts_Delete(Texts_Text *T, LONGINT beg, LONGINT end) {
    if (!T || !T->data || beg < 0 || end <= beg || beg >= T->len) return;
    if (end > T->len) end = T->len;
    
    LONGINT len = end - beg;
    memmove(T->data + beg, T->data + end, T->len - end);
    T->len -= len;
    T->data[T->len] = '\0';
}

void Texts_Append(Texts_Text *T, char *buf) {
    if (!T || !buf) return;
    init_log();
    
    // Add safety check to prevent hanging on non-null-terminated buffers
    LONGINT len = 0;
    LONGINT max_check = 1000;  // Limit string length check to prevent infinite loop
    while (len < max_check && buf[len] != '\0') {
        len++;
    }
    if (len >= max_check) {
        return;  // Buffer not properly null-terminated, skip
    }
    
    if (T->len + len < T->maxlen) {
        strcpy(T->data + T->len, buf);
        T->len += len;
    }
    
    // Output to console for immediate feedback (safer version)
    fputs(buf, stdout);
}

// Writer operations
void Texts_OpenWriter(Texts_Writer *W) {
    if (!W) return;
    W->buf = (char*)malloc(MAX_TEXT_LEN);
    W->pos = 0;
    W->maxlen = MAX_TEXT_LEN;
    if (W->buf) {
        W->buf[0] = '\0';
    }
}

void Texts_ClearWriter(Texts_Writer *W) {
    if (!W || !W->buf) return;
    W->pos = 0;
    W->buf[0] = '\0';
}

void Texts_WriteChar(Texts_Writer *W, char ch) {
    if (!W || !W->buf || W->pos >= W->maxlen - 1) return;
    W->buf[W->pos++] = ch;
    W->buf[W->pos] = '\0';
}

void Texts_WriteString(Texts_Writer *W, char *s) {
    if (!W || !W->buf || !s) return;
    
    LONGINT safety_count = 0;
    while (*s && W->pos < W->maxlen - 1 && safety_count < 10000) {
        W->buf[W->pos++] = *s++;
        safety_count++;
    }
    W->buf[W->pos] = '\0';
}

void Texts_WriteInt(Texts_Writer *W, LONGINT x, LONGINT n) {
    char temp[32];
    char format[16];
    
    if (!W || !W->buf) return;
    
    if (n > 0) {
        sprintf(format, "%%%dld", (int)n);
        sprintf(temp, format, (long)x);
    } else {
        sprintf(temp, "%ld", (long)x);
    }
    Texts_WriteString(W, temp);
}

void Texts_WriteHex(Texts_Writer *W, LONGINT x) {
    char temp[16];
    if (!W || !W->buf) return;
    sprintf(temp, "%08X", (unsigned int)x);
    Texts_WriteString(W, temp);
}

void Texts_WriteLn(Texts_Writer *W) {
    Texts_WriteChar(W, '\n');
}

// Scanner operations
void Texts_OpenScanner(Texts_Scanner *S, Texts_Text *T, LONGINT pos) {
    if (!S) return;
    S->text = T;
    S->pos = pos;
    S->class = Texts_Inval;
    S->c = ' ';
    S->nextCh = ' ';
    S->s[0] = '\0';
    S->i = 0;
    S->x = 0.0;
    
    // Read first character
    if (T && T->data && pos < T->len) {
        S->nextCh = T->data[pos];
    } else {
        S->nextCh = '\0';
    }
}

static void ReadChar(Texts_Scanner *S) {
    S->c = S->nextCh;
    S->pos++;
    if (S->text && S->text->data && S->pos < S->text->len) {
        S->nextCh = S->text->data[S->pos];
    } else {
        S->nextCh = '\0';
    }
}

void Texts_Scan(Texts_Scanner *S) {
    INTEGER i;
    
    if (!S) return;
    
    // Skip whitespace
    while (S->nextCh == ' ' || S->nextCh == '\t' || S->nextCh == '\r' || S->nextCh == '\n') {
        ReadChar(S);
    }
    
    if (S->nextCh == '\0') {
        S->class = Texts_End;
        return;
    }
    
    ReadChar(S);
    
    if (isalpha(S->c) || S->c == '_') {
        // Identifier or keyword
        i = 0;
        do {
            if (i < MAX_SCANNER_STRING - 1) {
                S->s[i++] = S->c;
            }
            ReadChar(S);
        } while (isalnum(S->c) || S->c == '_');
        S->s[i] = '\0';
        S->class = Texts_Name;
        
    } else if (isdigit(S->c)) {
        // Number
        S->i = 0;
        do {
            S->i = S->i * 10 + (S->c - '0');
            ReadChar(S);
        } while (isdigit(S->c));
        
        if (S->c == '.') {
            // Real number
            ReadChar(S);
            S->x = (REAL)S->i;
            REAL factor = 0.1;
            while (isdigit(S->c)) {
                S->x += (S->c - '0') * factor;
                factor *= 0.1;
                ReadChar(S);
            }
            S->class = Texts_Real;
        } else {
            S->class = Texts_Int;
        }
        
    } else if (S->c == '"') {
        // String
        i = 0;
        ReadChar(S);
        while (S->c != '"' && S->c != '\0' && i < MAX_SCANNER_STRING - 1) {
            S->s[i++] = S->c;
            ReadChar(S);
        }
        if (S->c == '"') {
            ReadChar(S);
        }
        S->s[i] = '\0';
        S->class = Texts_String;
        
    } else if (S->c == '\'') {
        // Character
        ReadChar(S);
        S->c = S->c;  // Store the character
        ReadChar(S);
        if (S->c == '\'') {
            ReadChar(S);
        }
        S->class = Texts_Char;
        
    } else {
        // Single character
        S->class = Texts_Char;
    }
}

// Simplified Oberon system operations
void Oberon_GetSelection(Texts_Text **T, LONGINT *beg, LONGINT *end, LONGINT *time) {
    // Simplified: no actual selection, return dummy values
    *T = NULL;
    *beg = 0;
    *end = 0;
    *time = -1;  // Indicates no selection
}

void Oberon_Collect(LONGINT option) {
    // Simplified: do nothing (garbage collection placeholder)
    (void)option;  // Suppress unused parameter warning
}
