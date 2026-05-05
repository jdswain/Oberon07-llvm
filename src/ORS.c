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

// ORS.c - Oberon Scanner (Lexical Analyzer) Implementation
// Uses new conventions with ORS_ prefix, Texts, and proper types

#include "ORS.h"
#include "Oberon.h"
#include "Texts.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <math.h>

// Constants
#define TAB 0x09
#define LF  0x0A
#define CR  0x0D

// Global variables
ORS_Ident ORS_id;                    // Current identifier
LONGINT ORS_ival;                    // Current integer value
REAL ORS_rval;                       // Current real value
LONGINT ORS_slen;                    // Current string length
char ORS_str[ORS_STRING_LEN];        // Current string value
INTEGER ORS_errcnt;                  // Error count

// Private variables
static Texts_Text *source_text;
static LONGINT source_pos;
static char ch;                      // Current character
static INTEGER errpos;               // Error position
static INTEGER line;                 // Current line number
static INTEGER col;                  // Current column number

// Keyword table
typedef struct {
    char *name;
    ORS_Symbol sym;
} KeyWord;

static KeyWord keyTab[] = {
    {"ARRAY", ORS_array},
    {"BEGIN", ORS_begin},
    {"BY", ORS_by},
    {"CASE", ORS_case},
    {"CONST", ORS_const},
    {"DIV", ORS_div},
    {"DO", ORS_do},
    {"ELSE", ORS_else},
    {"ELSIF", ORS_elsif},
    {"END", ORS_end},
    {"FALSE", ORS_false},
    {"FOR", ORS_for},
    {"IF", ORS_if},
    {"IMPORT", ORS_import},
    {"IN", ORS_in},
    {"IS", ORS_is},
    {"MOD", ORS_mod},
    {"MODULE", ORS_module},
    {"NIL", ORS_nil},
    {"NOT", ORS_not},
    {"OF", ORS_of},
    {"OR", ORS_or},
    {"POINTER", ORS_pointer},
    {"PROCEDURE", ORS_procedure},
    {"RECORD", ORS_record},
    {"REPEAT", ORS_repeat},
    {"RETURN", ORS_return},
    {"THEN", ORS_then},
    {"TO", ORS_to},
    {"TRUE", ORS_true},
    {"TYPE", ORS_type},
    {"UNTIL", ORS_until},
    {"VAR", ORS_var},
    {"WEAK", ORS_weak},
    {"WHILE", ORS_while},
    {NULL, ORS_null}
};

// Forward declarations
static void ReadChar(void);
static void ReadString(void);
static void ReadNumber(INTEGER *sym);
static void ReadScaleFactor(void);
static void ReadIdent(void);
static void Comment(void);

// Error reporting
void ORS_Mark(char *msg) {
    INTEGER p;

    p = source_pos - 1;  // Position of error
    if (p > errpos && ORS_errcnt < 25) {
        printf("  pos %d [%d:%d]  %s\n", p, line, col, msg);
        ORS_errcnt++;
    }
    errpos = p + 4;  // Avoid duplicate error messages
}

// Get current position in source
LONGINT ORS_Pos(void) {
    return source_pos;
}

// Read next character from source
static void ReadChar(void) {
    if (source_text && source_pos < source_text->len) {
        ch = source_text->data[source_pos];
        source_pos++;
        if (ch == LF) { line++; col = 0; } else { col++; }
    } else {
        ch = 0;  // EOF
    }
}

// Read string literal
static void ReadString(void) {
    INTEGER i = 0;
    ReadChar();  // Skip opening quote
    
    while (ch != '"' && ch != 0 && ch != CR && ch != LF) {
        if (i < ORS_STRING_LEN - 1) {
            ORS_str[i] = ch;
            i++;
        }
        ReadChar();
    }
    
    ORS_str[i] = 0;
    ORS_slen = i + 1;  // Include null terminator
    
    if (ch == '"') {
        ReadChar();  // Skip closing quote
    } else {
        ORS_Mark("string not terminated");
    }
}

// Read scale factor for real numbers (E notation)
static void ReadScaleFactor(void) {
    INTEGER sign;
    REAL e;
    INTEGER exp;

    sign = 1;
    ReadChar();  // Skip 'E' or 'D'

    if (ch == '+') {
        ReadChar();
    } else if (ch == '-') {
        sign = -1;
        ReadChar();
    }

    exp = 0;
    while (isdigit(ch)) {
        exp = exp * 10 + (ch - '0');
        ReadChar();
    }

    if (exp <= 38) {
        e = 1.0;
        while (exp > 0) {
            e = e * 10.0;
            exp--;
        }
        if (sign > 0) {
            ORS_rval = ORS_rval * e;
        } else {
            ORS_rval = ORS_rval / e;
        }
    } else {
        ORS_Mark("too large");
        ORS_rval = 0.0;
    }
}

// Read number (integer or real)
static void ReadNumber(INTEGER *sym) {
    INTEGER i, k, d, h;
    REAL x;
    INTEGER digits[16];  // Store digit values for potential hex conversion
    
    ORS_ival = 0;
    k = 0;
    
    // Read digits and hex characters (0-9, A-F)
    do {
        if (k < 16) {  // Avoid overflow
            if (ch >= '0' && ch <= '9') {
                d = ch - '0';
            } else if (ch >= 'A' && ch <= 'F') {
                d = ch - 'A' + 10;
            } else {
                break;  // Not a valid digit/hex character
            }
            
            digits[k] = d;  // Store for potential hex conversion
            if (ORS_ival <= (LONGINT)(2147483647 - d) / 10) {
                ORS_ival = ORS_ival * 10 + d;  // Assume decimal for now
                k++;
            } else {
                ORS_Mark("number too large");
                ORS_ival = 0;
                break;
            }
        }
        ReadChar();
    } while ((ch >= '0' && ch <= '9') || (ch >= 'A' && ch <= 'F'));
    
    if (ch == '.') {
        ReadChar();
        if (ch == '.') {
            // This is ".." (range operator), back up
            *sym = ORS_int;
            ch = 0x7F;  // Special marker for ".."
        } else {
	  *sym = ORS_real;
            // Real number
            x = (REAL)ORS_ival;
            ORS_rval = x;
            i = 0;
            
            while (isdigit(ch)) {
                x = (ch - '0');
                i++;
                ReadChar();
                ORS_rval = ORS_rval + x / pow(10.0, i);
            }
            
            if (ch == 'E' || ch == 'D') {
                ReadScaleFactor();
            }
        }
    } else if (ch == 'H') {
	  *sym = ORS_int;
        // Hexadecimal number - convert stored digits from decimal to hex interpretation
        ReadChar();
        ORS_ival = 0;
        for (i = 0; i < k; i++) {
            h = digits[i];
            // h is already correct: 0-9 = 0-9, A-F = 10-15
            if (ORS_ival <= (LONGINT)0x0FFFFFFF) {  // Check for hex overflow
                ORS_ival = ORS_ival * 16 + h;  // Build hex value
            } else {
                ORS_Mark("hexadecimal number too large");
                ORS_ival = 0;
                break;
            }
        }
    } else if (ch == 'X') {
	  *sym = ORS_char;
        // Character constant - convert stored digits to hex value
        ReadChar();
        ORS_ival = 0;
        for (i = 0; i < k; i++) {
            h = digits[i];
            // h is already correct: 0-9 = 0-9, A-F = 10-15
            ORS_ival = ORS_ival * 16 + h;
        }
        if (ORS_ival >= 256) {
            ORS_Mark("invalid character");
            ORS_ival = 0;
        }
    } else {
	  *sym = ORS_int;
	}
    // If no suffix, ORS_ival already contains the decimal interpretation
}

// Read identifier
static void ReadIdent(void) {
    INTEGER i;
    
    i = 0;
    do {
        if (i < ORS_IDENT_LEN - 1) {
            ORS_id[i] = ch;
            i++;
        }
        ReadChar();
    } while (isalnum(ch) || ch == '_');
    
    ORS_id[i] = 0;
}

// Skip comment
static void Comment(void) {
    ReadChar();  // Skip '*'
    
    do {
        while (ch != '*' && ch != 0) {
            if (ch == '(' && source_pos < source_text->len && 
                source_text->data[source_pos] == '*') {
                Comment();  // Nested comment
            } else {
                ReadChar();
            }
        }
        
        if (ch == '*') {
            ReadChar();
        }
    } while (ch != ')' && ch != 0);
    
    if (ch == ')') {
        ReadChar();
    } else {
        ORS_Mark("comment not closed");
    }
}

// Get next symbol
void ORS_Get(INTEGER *sym) {
    INTEGER k;
    INTEGER loop_count = 0;
    
    // Skip whitespace and comments with safety counter
    while (ch != 0 && (ch <= ' ' || (ch == '(' && source_pos < source_text->len && 
                                     source_text->data[source_pos] == '*'))) {
        loop_count++;
        if (loop_count > 1000) {  // Safety limit to prevent infinite loops
            ch = 0;  // Force EOF
            break;
        }
        
        if (ch == '(' && source_pos < source_text->len && 
            source_text->data[source_pos] == '*') {
            ReadChar();  // Skip '('
            Comment();   // Parse comment
        } else {
            ReadChar();  // Skip whitespace
        }
    }
    
    if (isalpha(ch)) {
        ReadIdent();
        
        // Check for keyword
        k = 0;
        while (keyTab[k].name != NULL) {
            if (strcmp(ORS_id, keyTab[k].name) == 0) {
                *sym = keyTab[k].sym;
                return;
            }
            k++;
        }
        *sym = ORS_ident;
        
    } else if (isdigit(ch)) {
        ReadNumber(sym);
        
    } else {
        switch (ch) {
            case 0:
                *sym = ORS_eof;
                break;
            case '"':
                ReadString();
                *sym = ORS_string;
                break;
            case '\'':
                ReadChar();
                ORS_ival = ch;
                ReadChar();
                if (ch == '\'') {
                    ReadChar();
                    *sym = ORS_char;
                } else {
                    ORS_Mark("' expected");
                    *sym = ORS_char;
                }
                break;
            case '#':
                ReadChar();
                *sym = ORS_neq;
                break;
            case '&':
                ReadChar();
                *sym = ORS_and;
                break;
            case '(':
                ReadChar();
                *sym = ORS_lparen;
                break;
            case ')':
                ReadChar();
                *sym = ORS_rparen;
                break;
            case '*':
                ReadChar();
                *sym = ORS_times;
                break;
            case '+':
                ReadChar();
                *sym = ORS_plus;
                break;
            case ',':
                ReadChar();
                *sym = ORS_comma;
                break;
            case '-':
                ReadChar();
                *sym = ORS_minus;
                break;
            case '.':
                ReadChar();
                if (ch == '.') {
                    ReadChar();
                    *sym = ORS_upto;
                } else {
                    *sym = ORS_period;
                }
                break;
            case '/':
                ReadChar();
                *sym = ORS_rdiv;
                break;
            case ':':
                ReadChar();
                if (ch == '=') {
                    ReadChar();
                    *sym = ORS_becomes;
                } else {
                    *sym = ORS_colon;
                }
                break;
            case ';':
                ReadChar();
                *sym = ORS_semicolon;
                break;
            case '<':
                ReadChar();
                if (ch == '=') {
                    ReadChar();
                    *sym = ORS_leq;
                } else {
                    *sym = ORS_lss;
                }
                break;
            case '=':
                ReadChar();
                *sym = ORS_eql;
                break;
            case '>':
                ReadChar();
                if (ch == '=') {
                    ReadChar();
                    *sym = ORS_geq;
                } else {
                    *sym = ORS_gtr;
                }
                break;
            case '[':
                ReadChar();
                *sym = ORS_lbrak;
                break;
            case ']':
                ReadChar();
                *sym = ORS_rbrak;
                break;
            case '^':
                ReadChar();
                *sym = ORS_arrow;
                break;
            case '{':
                ReadChar();
                *sym = ORS_lbrace;
                break;
            case '|':
                ReadChar();
                *sym = ORS_bar;
                break;
            case '}':
                ReadChar();
                *sym = ORS_rbrace;
                break;
            case '~':
                ReadChar();
                *sym = ORS_not;
                break;
            case 0x7F:  // Special marker for ".."
                ReadChar();
                *sym = ORS_upto;
                break;
            default:
                ReadChar();
                *sym = ORS_null;
                ORS_Mark("illegal character");
                break;
        }
    }
}

// Copy current identifier
void ORS_CopyId(ORS_Ident dest) {
    strcpy(dest, ORS_id);
}

// Initialize scanner
void ORS_Init(Texts_Text *T, LONGINT pos) {
    source_text = T;
    source_pos = pos;
    ORS_errcnt = 0;
    errpos = 0;
    line = 1;
    col = 0;

    // Initialize scanner state
    ORS_id[0] = 0;
    ORS_ival = 0;
    ORS_rval = 0.0;
    ORS_slen = 0;
    ORS_str[0] = 0;
    
    // Read first character
    ReadChar();
}
