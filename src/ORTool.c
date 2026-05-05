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

// ORTool.c - Oberon Tool for decoding symbol and object files
// Translated from ORTool.Mod by N.Wirth

#include "ORTool.h"
#include "Oberon.h"
#include "Texts.h"
#include "Files.h"
#include "ORB.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Global variables
static Texts_Writer W;
static INTEGER Form;  // result of ReadType
static char mnemo0[16][4];  // mnemonics for format 0 instructions
static char mnemo1[16][4];  // mnemonics for format 1 instructions

// Forward declarations
static void ReadType(Files_Rider *R);

// Read signed byte from file
static void Read(Files_Rider *R, INTEGER *n) {
    BYTE b;
    Files_ReadByte(R, &b);
    if (b < 0x80) {
        *n = b;
    } else {
        *n = b - 0x100;
    }
}

// Read and decode type information from symbol file
static void ReadType(Files_Rider *R) {
    INTEGER key, len, lev, size, off;
    INTEGER ref, mno, class, form, readonly;
    char name[32], modname[32];
    
    Read(R, &ref);
    Texts_Write(&W, ' ');
    Texts_Write(&W, '[');
    
    if (ref < 0) {
        Texts_Write(&W, '^');
        Texts_WriteInt(&W, -ref, 1);
    } else {
        Texts_WriteInt(&W, ref, 1);
        Read(R, &form);
        Texts_WriteString(&W, "  form = ");
        Texts_WriteInt(&W, form, 1);
        
        if (form == ORB_Pointer) {
            ReadType(R);
        } else if (form == ORB_Array) {
            ReadType(R);
            Files_ReadNum(R, &len);
            Files_ReadNum(R, &size);
            Texts_WriteString(&W, "  len = ");
            Texts_WriteInt(&W, len, 1);
            Texts_WriteString(&W, "  size = ");
            Texts_WriteInt(&W, size, 1);
        } else if (form == ORB_Record) {
            ReadType(R);  // base type
            Files_ReadNum(R, &off);
            Texts_WriteString(&W, "  exno = ");
            Texts_WriteInt(&W, off, 1);
            Files_ReadNum(R, &off);
            Texts_WriteString(&W, "  extlev = ");
            Texts_WriteInt(&W, off, 1);
            Files_ReadNum(R, &size);
            Texts_WriteString(&W, "  size = ");
            Texts_WriteInt(&W, size, 1);
            Texts_Write(&W, ' ');
            Texts_Write(&W, '{');
            Read(R, &class);
            
            while (class != 0) {  // fields
                Files_ReadString(R, name);
                if (name[0] != 0) {
                    Texts_Write(&W, ' ');
                    Texts_WriteString(&W, name);
                    ReadType(R);
                } else {
                    Texts_WriteString(&W, " --");
                }
                Files_ReadNum(R, &off);
                Texts_WriteInt(&W, off, 4);
                Read(R, &class);
            }
            Texts_Write(&W, '}');
        } else if (form == ORB_Proc) {
            ReadType(R);
            Texts_Write(&W, '(');
            Read(R, &class);
            
            while (class != 0) {
                Texts_WriteString(&W, " class = ");
                Texts_WriteInt(&W, class, 1);
                Read(R, &readonly);
                if (readonly == 1) {
                    Texts_Write(&W, '#');
                }
                ReadType(R);
                Read(R, &class);
            }
            Texts_Write(&W, ')');
        }
        
        Files_ReadString(R, modname);
        if (modname[0] != 0) {
            Files_ReadInt(R, &key);
            Files_ReadString(R, name);
            Texts_Write(&W, ' ');
            Texts_WriteString(&W, modname);
            Texts_Write(&W, '.');
            Texts_WriteString(&W, name);
            Texts_WriteHex(&W, key);
        }
    }
    
    Form = form;
    Texts_Write(&W, ']');
}

// Decode symbol file
void ORTool_DecSym(void) {
    INTEGER class, typno, k;
    char name[32];
    Files_File *F;
    Files_Rider R;
    Texts_Scanner S;
    
    Texts_OpenScanner(&S, Oberon_Par.text, Oberon_Par.pos);
    Texts_Scan(&S);
    
    if (S.class == Texts_Name) {
        Texts_WriteString(&W, "OR-decode ");
        Texts_WriteString(&W, S.s);
        Texts_WriteLn(&W);
        Texts_Append(Oberon_Log, W.buf);
        Texts_ClearWriter(&W);
        
        F = Files_Old(S.s);
        if (F != NULL) {
            Files_Set(&R, F, 0);
            Files_ReadInt(&R, &k);
            Files_ReadInt(&R, &k);
            Files_ReadString(&R, name);
            Texts_WriteString(&W, name);
            Texts_WriteHex(&W, k);
            Read(&R, &class);
            Texts_WriteInt(&W, class, 3);  // sym file version
            
            if (class == ORB_versionkey) {
                Texts_WriteLn(&W);
                Read(&R, &class);
                
                while (class != 0) {
                    Texts_WriteInt(&W, class, 4);
                    Files_ReadString(&R, name);
                    Texts_Write(&W, ' ');
                    Texts_WriteString(&W, name);
                    ReadType(&R);
                    
                    if (class == ORB_Typ) {
                        Texts_Write(&W, '(');
                        Read(&R, &class);
                        while (class != 0) {  // pointer base fixup
                            Texts_WriteString(&W, " ->");
                            Texts_WriteInt(&W, class, 4);
                            Read(&R, &class);
                        }
                        Texts_Write(&W, ')');
                    } else if ((class == ORB_Const) || (class == ORB_Var)) {
                        Files_ReadNum(&R, &k);
                        Texts_WriteInt(&W, k, 5);  // Reals, Strings!
                    }
                    
                    Texts_WriteLn(&W);
                    Texts_Append(Oberon_Log, W.buf);
                    Texts_ClearWriter(&W);
                    Read(&R, &class);
                }
            } else {
                Texts_WriteString(&W, " bad symfile version");
            }
        } else {
            Texts_WriteString(&W, " not found");
        }
        
        Texts_WriteLn(&W);
        Texts_Append(Oberon_Log, W.buf);
        Texts_ClearWriter(&W);
    }
}

// Write register name
static void WriteReg(LONGINT r) {
    Texts_Write(&W, ' ');
    if (r < 12) {
        Texts_WriteString(&W, " R");
        Texts_WriteInt(&W, r % 0x10, 1);
    } else if (r == 12) {
        Texts_WriteString(&W, "MT");
    } else if (r == 13) {
        Texts_WriteString(&W, "SB");
    } else if (r == 14) {
        Texts_WriteString(&W, "SP");
    } else {
        Texts_WriteString(&W, "LNK");
    }
}

// Decode instruction opcode
static void opcode(LONGINT w) {
    LONGINT k, op, u, a, b, c;
    
    k = (w / 0x40000000) % 4;
    a = (w / 0x1000000) % 0x10;
    b = (w / 0x100000) % 0x10;
    op = (w / 0x10000) % 0x10;
    u = (w / 0x20000000) % 2;
    
    if (k == 0) {
        Texts_WriteString(&W, mnemo0[op]);
        if (u == 1) {
            Texts_Write(&W, '\'');
        }
        WriteReg(a);
        WriteReg(b);
        WriteReg(w % 0x10);
    } else if (k == 1) {
        Texts_WriteString(&W, mnemo0[op]);
        if (u == 1) {
            Texts_Write(&W, '\'');
        }
        WriteReg(a);
        WriteReg(b);
        w = w % 0x10000;
        if (w >= 0x8000) {
            w = w - 0x10000;
        }
        Texts_WriteInt(&W, w, 7);
    } else if (k == 2) {  // LDR/STR
        if (u == 1) {
            Texts_WriteString(&W, "STR ");
        } else {
            Texts_WriteString(&W, "LDR");
        }
        WriteReg(a);
        WriteReg(b);
        w = w % 0x100000;
        if (w >= 0x80000) {
            w = w - 0x100000;
        }
        Texts_WriteInt(&W, w, 8);
    } else if (k == 3) {  // Branch instr
        Texts_Write(&W, 'B');
        if ((w / 0x10000000) % 2 == 1) {
            Texts_Write(&W, 'L');
        }
        Texts_WriteString(&W, mnemo1[a]);
        if (u == 0) {
            WriteReg(w % 0x10);
        } else {
            w = w % 0x100000;
            if (w >= 0x80000) {
                w = w - 0x100000;
            }
            Texts_WriteInt(&W, w, 8);
        }
    }
}

// Decode object file
void ORTool_DecObj(void) {
    INTEGER class, i, n, key, size, fix, adr, data, len;
    char ch;
    char name[32];
    Files_File *F;
    Files_Rider R;
    Texts_Scanner S;
    
    Texts_OpenScanner(&S, Oberon_Par.text, Oberon_Par.pos);
    Texts_Scan(&S);
    
    if (S.class == Texts_Name) {
        Texts_WriteString(&W, "decode ");
        Texts_WriteString(&W, S.s);
        F = Files_Old(S.s);
        
        if (F != NULL) {
            Files_Set(&R, F, 0);
            Files_ReadString(&R, name);
            Texts_WriteLn(&W);
            Texts_WriteString(&W, name);
            Files_ReadInt(&R, &key);
            Texts_WriteHex(&W, key);
            Read(&R, &class);
            Texts_WriteInt(&W, class, 4);  // version
            Files_ReadInt(&R, &size);
            Texts_WriteInt(&W, size, 6);
            Texts_WriteLn(&W);
            
            // Imports
            Texts_WriteString(&W, "imports:");
            Texts_WriteLn(&W);
            Files_ReadString(&R, name);
            while (name[0] != 0) {
                Texts_Write(&W, '\t');
                Texts_WriteString(&W, name);
                Files_ReadInt(&R, &key);
                Texts_WriteHex(&W, key);
                Texts_WriteLn(&W);
                Files_ReadString(&R, name);
            }
            
            // Type descriptors
            Texts_WriteString(&W, "type descriptors");
            Texts_WriteLn(&W);
            Files_ReadInt(&R, &n);
            n = n / 4;
            i = 0;
            while (i < n) {
                Files_ReadInt(&R, &data);
                Texts_WriteHex(&W, data);
                i++;
            }
            Texts_WriteLn(&W);
            
            // Data
            Texts_WriteString(&W, "data");
            Files_ReadInt(&R, &data);
            Texts_WriteInt(&W, data, 6);
            Texts_WriteLn(&W);
            
            // Strings
            Texts_WriteString(&W, "strings");
            Texts_WriteLn(&W);
            Files_ReadInt(&R, &n);
            i = 0;
            while (i < n) {
                Files_Read(&R, &ch);
                Texts_Write(&W, ch);
                i++;
            }
            Texts_WriteLn(&W);
            
            // Code
            Texts_WriteString(&W, "code");
            Texts_WriteLn(&W);
            Files_ReadInt(&R, &n);
            i = 0;
            while (i < n) {
                Files_ReadInt(&R, &data);
                Texts_WriteInt(&W, i, 4);
                Texts_Write(&W, '\t');
                Texts_WriteHex(&W, data);
                Texts_Write(&W, '\t');
                opcode(data);
                Texts_WriteLn(&W);
                i++;
            }
            
            // Commands
            Texts_WriteString(&W, "commands:");
            Texts_WriteLn(&W);
            Files_ReadString(&R, name);
            while (name[0] != 0) {
                Texts_Write(&W, '\t');
                Texts_WriteString(&W, name);
                Files_ReadInt(&R, &adr);
                Texts_WriteInt(&W, adr, 5);
                Texts_WriteLn(&W);
                Files_ReadString(&R, name);
            }
            
            // Entries
            Texts_WriteString(&W, "entries");
            Texts_WriteLn(&W);
            Files_ReadInt(&R, &n);
            i = 0;
            while (i < n) {
                Files_ReadInt(&R, &adr);
                Texts_WriteInt(&W, adr, 6);
                i++;
            }
            Texts_WriteLn(&W);
            
            // Pointer refs
            Texts_WriteString(&W, "pointer refs");
            Texts_WriteLn(&W);
            Files_ReadInt(&R, &adr);
            while (adr != -1) {
                Texts_WriteInt(&W, adr, 6);
                Files_ReadInt(&R, &adr);
            }
            Texts_WriteLn(&W);
            
            // Fixups and entry point
            Files_ReadInt(&R, &data);
            Texts_WriteString(&W, "fixP = ");
            Texts_WriteInt(&W, data, 8);
            Texts_WriteLn(&W);
            
            Files_ReadInt(&R, &data);
            Texts_WriteString(&W, "fixD = ");
            Texts_WriteInt(&W, data, 8);
            Texts_WriteLn(&W);
            
            Files_ReadInt(&R, &data);
            Texts_WriteString(&W, "fixT = ");
            Texts_WriteInt(&W, data, 8);
            Texts_WriteLn(&W);
            
            Files_ReadInt(&R, &data);
            Texts_WriteString(&W, "entry = ");
            Texts_WriteInt(&W, data, 8);
            Texts_WriteLn(&W);
            
            Files_Read(&R, &ch);
            if (ch != 'O') {
                Texts_WriteString(&W, "format error");
                Texts_WriteLn(&W);
            }
        } else {
            Texts_WriteString(&W, " not found");
            Texts_WriteLn(&W);
        }
        
        Texts_Append(Oberon_Log, W.buf);
        Texts_ClearWriter(&W);
    }
}

// Initialize module
void ORTool_Init(void) {
    Texts_OpenWriter(&W);
    Texts_WriteString(&W, "ORTool 18.2.2013");
    Texts_WriteLn(&W);
    Texts_Append(Oberon_Log, W.buf);
    Texts_ClearWriter(&W);
    
    // Initialize instruction mnemonics
    strcpy(mnemo0[0], "MOV");
    strcpy(mnemo0[1], "LSL");
    strcpy(mnemo0[2], "ASR");
    strcpy(mnemo0[3], "ROR");
    strcpy(mnemo0[4], "AND");
    strcpy(mnemo0[5], "ANN");
    strcpy(mnemo0[6], "IOR");
    strcpy(mnemo0[7], "XOR");
    strcpy(mnemo0[8], "ADD");
    strcpy(mnemo0[9], "SUB");
    strcpy(mnemo0[10], "MUL");
    strcpy(mnemo0[11], "DIV");
    strcpy(mnemo0[12], "FAD");
    strcpy(mnemo0[13], "FSB");
    strcpy(mnemo0[14], "FML");
    strcpy(mnemo0[15], "FDV");
    
    strcpy(mnemo1[0], "MI ");
    strcpy(mnemo1[8], "PL");
    strcpy(mnemo1[1], "EQ ");
    strcpy(mnemo1[9], "NE ");
    strcpy(mnemo1[2], "LS ");
    strcpy(mnemo1[10], "HI ");
    strcpy(mnemo1[5], "LT ");
    strcpy(mnemo1[13], "GE ");
    strcpy(mnemo1[6], "LE ");
    strcpy(mnemo1[14], "GT ");
    strcpy(mnemo1[15], "NO ");
}
