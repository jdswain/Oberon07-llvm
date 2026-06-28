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

/* ORB.c - Symbol Table Management */
/* Original: NW 25.6.2014 / AP 4.3.2020 / 8.3.2019 in Oberon-07 */
/* Definition of data types Object and Type, which together form the data structure
   called "symbol table". Contains procedures for creation of Objects, and for search:
   NewObj, this, thisimport, thisfield (and OpenScope, CloseScope).
   Handling of import and export, i.e. reading and writing of "symbol files" is done by procedures
   Import and Export. Thismodule contains the list of standard identifiers, with which
   the symbol table (universe), and that of the pseudo-module SYSTEM are initialized. */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stdint.h>
#include "ORS.h"
#include "ORB.h"

/* Global variables */
ObjectPtr topScope = NULL;
ObjectPtr universe = NULL;
ObjectPtr systemScope = NULL;  /* renamed from system */
TypePtr byteType = NULL;
TypePtr boolType = NULL;
TypePtr charType = NULL;
TypePtr intType = NULL;
TypePtr longType = NULL;
TypePtr realType = NULL;
TypePtr setType = NULL;
TypePtr nilType = NULL;
TypePtr noType = NULL;
TypePtr strType = NULL;

/* Static variables */
static int nofmod;
static int Ref;
static TypePtr typtab[maxTypTab];

/* Source file directory for output file placement */
static char source_dir[256] = "";

/* Search paths for symbol files */
#define MAX_SEARCH_PATHS 16
static char search_paths[MAX_SEARCH_PATHS][256];
static int num_search_paths = 0;

/* All file operations now handled by Files.h/Files.c */


/* Symbol table operations */
void NewObj(ObjectPtr *obj, const char *id, int class) {
    ObjectPtr new_obj, x;
    
    x = topScope;
    while ((x->next != NULL) && (strcmp(x->next->name, id) != 0)) {
        x = x->next;
    }
    
    if (x->next == NULL) {
        new_obj = (ObjectPtr)calloc(1, sizeof(ORB_Object));
        strcpy(new_obj->name, id);
        new_obj->class = class;
        new_obj->next = NULL;
        new_obj->rdo = false;
        new_obj->dsc = NULL;
        x->next = new_obj;
        *obj = new_obj;
    } else {
        *obj = x->next;
        ORS_Mark("mult def");
    }
}

ObjectPtr thisObj(void) {
    ObjectPtr s, x;
    
    s = topScope;
    do {
        x = s->next;
        while ((x != NULL) && (strcmp(x->name, ORS_id) != 0)) {
            x = x->next;
        }
        s = s->dsc;
    } while ((x == NULL) && (s != NULL));
    
    return x;
}

ObjectPtr thisimport(ObjectPtr mod) {
    ObjectPtr obj = NULL;
    
    if (mod->rdo) {
        if (mod->name[0] != '\0') {
            obj = mod->dsc;
            while ((obj != NULL) && (strcmp(obj->name, ORS_id) != 0)) {
                obj = obj->next;
            }
        }
    }
    
    return obj;
}

ObjectPtr thisfield(TypePtr rec) {
    ObjectPtr fld = rec->dsc;
    
    while ((fld != NULL) && (strcmp(fld->name, ORS_id) != 0)) {
        fld = fld->next;
    }
    
    return fld;
}

void OpenScope(void) {
    ObjectPtr s = (ObjectPtr)calloc(1, sizeof(ORB_Object));
    s->class = ORB_Head;
    s->dsc = topScope;
    s->next = NULL;
    topScope = s;
}

void CloseScope(void) {
    topScope = topScope->dsc;
}

/* Import/Export operations */
void SetSourceDirectory(const char *source_filename) {
    int i = strlen(source_filename) - 1;
    
    // Find the last directory separator
    while (i >= 0 && source_filename[i] != '/' && source_filename[i] != '\\') {
        i--;
    }
    
    if (i >= 0) {
        // Copy directory path including the separator
        int len = i + 1;
        if (len >= sizeof(source_dir)) len = sizeof(source_dir) - 1;
        strncpy(source_dir, source_filename, len);
        source_dir[len] = '\0';
    } else {
        // No directory separator found, use current directory
        source_dir[0] = '\0';
    }
}

const char *GetSourceDir(void) {
    return source_dir;
}

void MakeFileName(char *FName, const char *name, const char *ext) {
    int i = 0, j = 0;
    int maxlen = 255;  /* FName assumed to be at least 256 chars */

    // Start with the source directory
    while (source_dir[i] != '\0' && i < maxlen - 40) {
        FName[i] = source_dir[i];
        i++;
    }

    // Add the module name
    j = 0;
    while (name[j] != '\0' && i < maxlen - 5) {
        FName[i] = name[j];
        i++;
        j++;
    }

    // Add the extension
    j = 0;
    while (ext[j] != '\0' && i < maxlen) {
        FName[i] = ext[j];
        i++;
        j++;
    }

    FName[i] = '\0';
}

void AddSearchPath(const char *path) {
    if (num_search_paths < MAX_SEARCH_PATHS) {
        strncpy(search_paths[num_search_paths], path, 255);
        search_paths[num_search_paths][255] = '\0';
        /* Ensure trailing slash */
        int len = strlen(search_paths[num_search_paths]);
        if (len > 0 && path[len-1] != '/' && path[len-1] != '\\') {
            if (len < 254) {
                search_paths[num_search_paths][len] = '/';
                search_paths[num_search_paths][len+1] = '\0';
            }
        }
        num_search_paths++;
    }
}

static Files_File *FindSymbolFile(const char *modname) {
    char fname[256];
    Files_File *F;
    int i;

    /* First try source_dir (current behavior — backward compatible) */
    MakeFileName(fname, modname, ".smb");
    F = Files_Old(fname);
    if (F != NULL) return F;

    /* Then try each search path */
    for (i = 0; i < num_search_paths; i++) {
        int j = 0, k = 0;
        while (search_paths[i][j] != '\0' && j < 215) {
            fname[j] = search_paths[i][j]; j++;
        }
        while (modname[k] != '\0' && j < 250) {
            fname[j] = modname[k]; j++; k++;
        }
        fname[j++] = '.'; fname[j++] = 's'; fname[j++] = 'm'; fname[j++] = 'b';
        fname[j] = '\0';
        F = Files_Old(fname);
        if (F != NULL) return F;
    }
    return NULL;
}

static ObjectPtr ThisORB_Module(const char *name, const char *orgname, bool decl, int32_t key) {
    ModulePtr mod;
    ObjectPtr obj, obj1;
    
    obj1 = topScope;
    obj = obj1->next;
    
    /* Search for module */
    while ((obj != NULL) && (strcmp(((ModulePtr)obj)->orgname, orgname) != 0)) {
        obj1 = obj;
        obj = obj1->next;
    }
    
    if (obj == NULL) {
        /* New module, search for alias */
        obj = topScope->next;
        while ((obj != NULL) && (strcmp(obj->name, name) != 0)) {
            obj = obj->next;
        }
        
        if (obj == NULL) {
            /* Insert new module */
            mod = (ModulePtr)calloc(1, sizeof(ORB_Module));
            mod->base.class = ORB_Mod;
            mod->base.rdo = false;
            strcpy(mod->base.name, name);
            strcpy(mod->orgname, orgname);
            mod->base.val = key;
            mod->base.lev = nofmod;
            nofmod++;
            mod->base.dsc = NULL;
            mod->base.next = NULL;
            
            if (decl) {
                mod->base.type = noType;
            } else {
                mod->base.type = nilType;
            }
            
            obj1->next = (ObjectPtr)mod;
            obj = (ObjectPtr)mod;
        } else if (decl) {
            if (obj->type->form == ORB_NoTyp) {
                ORS_Mark("mult def");
            } else {
                ORS_Mark("invalid import order");
            }
        } else {
            ORS_Mark("conflict with alias");
        }
    } else if (decl) {
        /* ORB_Module already present, explicit import by declaration */
        if (obj->type->form == ORB_NoTyp) {
            ORS_Mark("mult def");
        } else {
            ORS_Mark("invalid import order");
        }
    }
    
    return obj;
}

static void Read(Files_Rider *R, int *x) {
    BYTE b;
    Files_ReadByte(R, &b);
    if (b < 0x80) {
        *x = b;
    } else {
        *x = b - 0x100;
    }
}

static void Write(Files_Rider *R, int x) {
    Files_WriteByte(R, (BYTE)x);
}

static void InType(Files_Rider *R, ObjectPtr thismod, TypePtr *T) {
    int32_t key;
    int ref, class, form, np, readonly;
    ObjectPtr fld, par, obj, mod, last;
    TypePtr t;
    char name[ORS_IDENT_LEN], modname[ORS_IDENT_LEN];
    
    Read(R, &ref);
    if (ref < 0) {
        *T = typtab[-ref];  /* Already read */
    } else {
        t = (TypePtr)calloc(1, sizeof(ORB_Type));
        *T = t;
        typtab[ref] = t;
        t->mno = thismod->lev;
        
        Read(R, &form);
        t->form = form;

        if (form == ORB_Int) {
            Files_ReadNum(R, &t->size);
        }

        if (form == ORB_Pointer) {
            InType(R, thismod, &t->base);
            t->size = 4;
        } else if (form == ORB_Array) {
            InType(R, thismod, &t->base);
            Files_ReadNum(R, &t->len);
            Files_ReadNum(R, &t->size);
        } else if (form == ORB_Record) {
            InType(R, thismod, &t->base);
            if (t->base->form == ORB_NoTyp) {
                t->base = NULL;
                obj = NULL;
            } else {
                obj = t->base->dsc;
            }
            
            Files_ReadNum(R, &t->len);     /* TD adr/exno */
            Files_ReadNum(R, &t->nofpar);  /* ext level */
            Files_ReadNum(R, &t->size);
            
            Read(R, &class);
            last = NULL;
            
            while (class != 0) {  /* Fields */
                fld = (ObjectPtr)calloc(1, sizeof(ORB_Object));
                fld->class = class;
                Files_ReadString(R, fld->name);
                
                if (last == NULL) {
                    t->dsc = fld;
                } else {
                    last->next = fld;
                }
                last = fld;
                
                fld->expo = (fld->name[0] != '\0');
                /* Always read the field type — this matches the new
                   OutType that emits every field, so layout is exactly
                   reconstructed regardless of export. */
                InType(R, thismod, &fld->type);
                Files_ReadNum(R, &fld->val);
                Read(R, &class);
            }
            
            if (last == NULL) {
                t->dsc = obj;
            } else {
                last->next = obj;
            }
        } else if (form == ORB_Proc) {
            InType(R, thismod, &t->base);
            obj = NULL;
            np = 0;
            Read(R, &class);
            
            while (class != 0) {  /* Parameters */
                par = (ObjectPtr)calloc(1, sizeof(ORB_Object));
                par->class = class;
                Read(R, &readonly);
                par->rdo = (readonly == 1);
                InType(R, thismod, &par->type);
                par->next = obj;
                obj = par;
                np++;
                Read(R, &class);
            }
            
            t->dsc = obj;
            t->nofpar = np;
            t->size = 4;
        }
        
        /* Unify basic types with global type objects so that pointer
           equality in CompTypes works across module boundaries */
        if (form == ORB_Byte)        { free(t); t = byteType; *T = t; typtab[ref] = t; }
        else if (form == ORB_Bool)   { free(t); t = boolType; *T = t; typtab[ref] = t; }
        else if (form == ORB_Char)   { free(t); t = charType; *T = t; typtab[ref] = t; }
        else if (form == ORB_Int)    { LONGINT sz = t->size; free(t);
                                       t = (sz >= 8) ? longType : intType;
                                       *T = t; typtab[ref] = t; }
        else if (form == ORB_Real)   { free(t); t = realType; *T = t; typtab[ref] = t; }
        else if (form == ORB_Set)    { free(t); t = setType;  *T = t; typtab[ref] = t; }
        else if (form == ORB_NilTyp) { free(t); t = nilType;  *T = t; typtab[ref] = t; }
        else if (form == ORB_NoTyp)  { free(t); t = noType;   *T = t; typtab[ref] = t; }

        Files_ReadString(R, modname);
        if (modname[0] != '\0') {  /* Re-import */
            Files_ReadInt(R, &key);
            Files_ReadString(R, name);
            mod = ThisORB_Module(modname, modname, false, key);
            obj = mod->dsc;
            
            /* Search type */
            while ((obj != NULL) && (strcmp(obj->name, name) != 0)) {
                obj = obj->next;
            }
            
            if (obj != NULL) {
                *T = obj->type;  /* Type object found */
            } else {
                /* Insert new type object */
                obj = (ObjectPtr)calloc(1, sizeof(ORB_Object));
                strcpy(obj->name, name);
                obj->class = ORB_Typ;
                obj->next = mod->dsc;
                mod->dsc = obj;
                obj->type = t;
                t->mno = mod->lev;
                t->typobj = obj;
                *T = t;
            }
            typtab[ref] = *T;
        }
    }
}

void Import(char *modid, char *modid1) {
    int32_t key = 0;  /* Initialize to 0 */
    int class, k;
    ObjectPtr obj;
    TypePtr t;
    ObjectPtr thismod;
    char modname[ORS_IDENT_LEN];
    Files_File *F;
    Files_Rider R;
    
    if (strcmp(modid1, "SYSTEM") == 0) {
        thismod = ThisORB_Module(modid, modid1, true, key);
        nofmod--;
        thismod->lev = 0;
        thismod->dsc = systemScope;
        thismod->rdo = true;
    } else {
        F = FindSymbolFile(modid1);
        
        if (F != NULL) {
            Files_Set(&R, F, 0);
            Files_ReadInt(&R, &key);
            Files_ReadInt(&R, &key);
            Files_ReadString(&R, modname);
            thismod = ThisORB_Module(modid, modid1, true, key);
            thismod->rdo = true;
            
            Read(&R, &class);  /* version key */
            if (class != versionkey) {
                ORS_Mark("wrong version");
            }

            Read(&R, &class);
            while (class != 0) {
                obj = (ObjectPtr)calloc(1, sizeof(ORB_Object));
                obj->class = class;
                Files_ReadString(&R, obj->name);
                InType(&R, thismod, &obj->type);
                obj->lev = -thismod->lev;

                if (class == ORB_Typ) {
                    t = obj->type;
                    t->typobj = obj;
                    Read(&R, &k);
                    
                    /* Fixup bases of previously declared pointer types */
                    while (k != 0) {
                        typtab[k]->base = t;
                        Read(&R, &k);
                    }
                } else {
                    if (class == ORB_Const) {
                        if (obj->type->form == ORB_Real) {
                            Files_ReadInt(&R, &obj->val);
                        } else {
                            Files_ReadNum(&R, &obj->val);
                        }
                    } else if (class == ORB_Var) {
                        Files_ReadNum(&R, &obj->val);
                        obj->rdo = true;
                    }
                }
                
                obj->next = thismod->dsc;
                thismod->dsc = obj;
                Read(&R, &class);
            }
            
            Files_Register(F);
        } else {
            ORS_Mark("import not available");
        }
    }
}

static void OutType(Files_Rider *R, TypePtr t);

static void OutPar(Files_Rider *R, ObjectPtr par, int n) {
    int cl;
    
    if (n > 0) {
        OutPar(R, par->next, n-1);
        cl = par->class;
        Write(R, cl);
        if (par->rdo) {
            Write(R, 1);
        } else {
            Write(R, 0);
        }
        OutType(R, par->type);
    }
}

static void FindHiddenORB_Pointers(Files_Rider *R, TypePtr typ, int32_t offset) {
    ObjectPtr fld;
    int32_t i, n;
    
    if ((typ->form == ORB_Pointer) || (typ->form == ORB_NilTyp)) {
        Write(R, ORB_Fld);
        Write(R, 0);
        Files_WriteNum(R, offset);
    } else if (typ->form == ORB_Record) {
        fld = typ->dsc;
        while (fld != NULL) {
            FindHiddenORB_Pointers(R, fld->type, fld->val + offset);
            fld = fld->next;
        }
    } else if (typ->form == ORB_Array) {
        i = 0;
        n = typ->len;
        while (i < n) {
            FindHiddenORB_Pointers(R, typ->base, typ->base->size * i + offset);
            i++;
        }
    }
}

static void OutType(Files_Rider *R, TypePtr t) {
    ObjectPtr obj, mod, fld, bot;
    
    if (t->ref > 0) {
        /* Type was already output */
        Write(R, -t->ref);
    } else {
        obj = t->typobj;
        if (obj != NULL) {
            Write(R, Ref);
            t->ref = Ref;
            Ref++;
        } else {
            /* Anonymous */
            Write(R, 0);
        }
        
        Write(R, t->form);

        if (t->form == ORB_Int) {
            /* INTEGER (size 4) and LONGINT (size 8) share form ORB_Int;
               persist size so the importer can pick the right global. */
            Files_WriteNum(R, t->size);
        }

        if (t->form == ORB_Pointer) {
            OutType(R, t->base);
        } else if (t->form == ORB_Array) {
            OutType(R, t->base);
            Files_WriteNum(R, t->len);
            Files_WriteNum(R, t->size);
        } else if (t->form == ORB_Record) {
            if (t->base != NULL) {
                OutType(R, t->base);
                bot = t->base->dsc;
            } else {
                OutType(R, noType);
                bot = NULL;
            }
            
            /* Write TD byte offset (not exno) so importing modules
               can directly use SB + len for type tag computation */
            Files_WriteNum(R, t->len);

            Files_WriteNum(R, t->nofpar);
            Files_WriteNum(R, t->size);
            
            /* Emit every source-level field with its full type so the
               importing module can reconstruct the record's layout
               exactly. Non-exported fields go out with name="" (empty)
               — the importer keeps the slot but marks it not-exported,
               so designators like x.private from outside still fail
               cleanly. This replaces the earlier FindHiddenORB_Pointers
               flatten-pointers-only scheme, which left private non-
               pointer fields invisible to the importer (so imported
               record sizes were wrong). */
            fld = t->dsc;
            while (fld != bot) {
                Write(R, ORB_Fld);
                Files_WriteString(R, fld->expo ? fld->name : "");
                OutType(R, fld->type);
                Files_WriteNum(R, fld->val);
                fld = fld->next;
            }
            Write(R, 0);
        } else if (t->form == ORB_Proc) {
            OutType(R, t->base);
            OutPar(R, t->dsc, t->nofpar);
            Write(R, 0);
        }
        
        if ((t->mno > 0) && (obj != NULL)) {
            /* Re-export, output name */
            mod = topScope->next;
            while ((mod != NULL) && (mod->lev != t->mno)) {
                mod = mod->next;
            }
            
            if (mod != NULL) {
                Files_WriteString(R, ((ModulePtr)mod)->orgname);
                Files_WriteInt(R, mod->val);
                Files_WriteString(R, obj->name);
            } else {
                ORS_Mark("re-export not found");
                Write(R, 0);
            }
        } else {
            Write(R, 0);
        }
    }
}

void Export(const char *modid, BOOLEAN *newSF, int32_t *key) {
    int32_t x, sum, oldkey;
    ObjectPtr obj, obj0;
    char filename[256];
    Files_File *F, *F1;
    Files_Rider R, R1;
    
    Ref = ORB_Record + 1;
    MakeFileName(filename, modid, ".smb");
    
    /* Read old checksum first before overwriting file */
    F1 = Files_Old(filename);
    if (F1 != NULL) {
        Files_Set(&R1, F1, 4);
        Files_ReadInt(&R1, &oldkey);
        Files_Close(F1);
    } else {
        oldkey = 0; /* No old file exists */
    }
    
    F = Files_New(filename);
    Files_Set(&R, F, 0);
    
    Files_WriteInt(&R, 0);  /* placeholder */
    Files_WriteInt(&R, 0);  /* placeholder for key */
    Files_WriteString(&R, modid);
    Write(&R, versionkey);
    
    obj = topScope->next;
    while (obj != NULL) {
        if (obj->expo) {
            Write(&R, obj->class);
            Files_WriteString(&R, obj->name);
            OutType(&R, obj->type);
            
            if (obj->class == ORB_Typ) {
                if (obj->type->form == ORB_Record) {
                    obj0 = topScope->next;
                    /* Check whether this is base of previously declared pointer types */
                    while (obj0 != obj) {
                        if ((obj0->type->form == ORB_Pointer) && 
                            (obj0->type->base == obj->type) && 
                            (obj0->type->ref > 0)) {
                            Write(&R, obj0->type->ref);
                        }
                        obj0 = obj0->next;
                    }
                }
                Write(&R, 0);
            } else if (obj->class == ORB_Const) {
                if (obj->type->form == ORB_Proc) {
                    Files_WriteNum(&R, obj->exno);
                } else if (obj->type->form == ORB_Real) {
                    Files_WriteInt(&R, obj->val);
                } else if (obj->type->form == ORB_Array || obj->type->form == ORB_Record) {
                    // Structured constant: export offset from SB (varsize + str_offset)
                    extern LONGINT ORG_varsize;
                    Files_WriteNum(&R, ORG_varsize + obj->val);
                } else {
                    Files_WriteNum(&R, obj->val);
                }
            } else if (obj->class == ORB_Var) {
                Files_WriteNum(&R, obj->val);
            }
        }
        obj = obj->next;
    }
    
    /* Pad to 4-byte boundary */
    do {
        Write(&R, 0);
    } while (Files_Length(F) % 4 != 0);
    
    /* Clear type table */
    for (Ref = ORB_Record + 1; Ref < maxTypTab; Ref++) {
        typtab[Ref] = NULL;
    }
    
    /* Register (flush) the file before reading for checksum */
    Files_Register(F);
    
    /* Reopen the file for reading */
    F = Files_Old(filename);
    if (F == NULL) {
        *key = 0;
        return;
    }
    
    /* Compute checksum */
    Files_Set(&R, F, 0);
    sum = 0;
    Files_ReadInt(&R, &x);
    while (!R.eof) {
        sum = sum + x;
        Files_ReadInt(&R, &x);
    }
    
    if (sum != oldkey) {
        if (*newSF || (oldkey == 0)) {
            *key = sum;
            *newSF = true;
            // Reopen file for writing to update checksum
            Files_Close(F);
            F = Files_Update(filename);
            if (F) {
                Files_Set(&R, F, 4);
                Files_WriteInt(&R, sum);
                Files_Register(F);
                Files_Close(F);
            }
        } else {
            ORS_Mark("new symbol file inhibited");
        }
    } else {
        // Interface fingerprint unchanged — keep the existing key
        // so importers stay valid. We still need to patch the file's
        // key field: the rewrite above stamped a placeholder 0 there,
        // and leaving it would flip the on-disk hash every other
        // recompile (next run would read oldkey=0, see sum != 0,
        // patch with sum; the run after would read oldkey=sum, see
        // sum == sum, leave 0, and so on). Same patch as the
        // success branch above.
        *newSF = false;
        *key = sum;
        Files_Close(F);
        F = Files_Update(filename);
        if (F) {
            Files_Set(&R, F, 4);
            Files_WriteInt(&R, sum);
            Files_Register(F);
            Files_Close(F);
        }
    }
}

void ORB_Init(void) {
    topScope = universe;
    nofmod = 1;
}

/* Helper functions */
static TypePtr type(int ref, int form, int32_t size) {
    TypePtr tp = (TypePtr)calloc(1, sizeof(ORB_Type));
    tp->form = form;
    tp->size = size;
    tp->ref = ref;
    tp->base = NULL;
    typtab[ref] = tp;
    return tp;
}

static void enter(const char *name, int cl, TypePtr type, int32_t n) {
    ObjectPtr obj = (ObjectPtr)calloc(1, sizeof(ORB_Object));
    strcpy(obj->name, name);
    obj->class = cl;
    obj->type = type;
    obj->val = n;
    obj->dsc = NULL;
    
    if (cl == ORB_Typ) {
        type->typobj = obj;
    }
    
    obj->next = systemScope;
    systemScope = obj;
}

/* ORB_Module initialization - call this once at program start */
void ORB_Initialize(void) {
    /* Initialize basic types */
    byteType = type(ORB_Byte, ORB_Int, 1);
    boolType = type(ORB_Bool, ORB_Bool, 1);
    charType = type(ORB_Char, ORB_Char, 1);
    intType = type(ORB_Int, ORB_Int, 4);
    /* longType shares form ORB_Int but must NOT overwrite typtab[ORB_Int] */
    longType = (TypePtr)calloc(1, sizeof(ORB_Type));
    longType->form = ORB_Int;
    longType->size = 8;
    longType->ref = 0;
    longType->base = NULL;
    realType = type(ORB_Real, ORB_Real, 4);
    setType = type(ORB_Set, ORB_Set, 4);
    nilType = type(ORB_NilTyp, ORB_NilTyp, 4);
    noType = type(ORB_NoTyp, ORB_NoTyp, 4);
    strType = type(ORB_String, ORB_String, 8);
    
    /* Initialize universe with data types and in-line procedures;
       INTEGER is 16-bit, LONGINT is 32-bit, LONGREAL is synonym to REAL.
       LED, ADC, SBC; LDPSR, LDREG, REG, COND are not in language definition */
    systemScope = NULL;  /* n = procno*10 + nofpar */
    
    /* Functions */
    enter("UML", ORB_SFunc, intType, 132);
    enter("ROL", ORB_SFunc, intType, 122);
    enter("LSR", ORB_SFunc, intType, 112);
    enter("ASL", ORB_SFunc, intType, 102);
    enter("ORA", ORB_SFunc, intType, 92);
    enter("EOR", ORB_SFunc, intType, 82);
    enter("AND", ORB_SFunc, intType, 72);
    enter("LEN", ORB_SFunc, intType, 61);
    enter("CHR", ORB_SFunc, charType, 51);
    enter("ORD", ORB_SFunc, intType, 41);
    enter("FLT", ORB_SFunc, realType, 31);
    enter("FLOOR", ORB_SFunc, intType, 21);
    enter("ODD", ORB_SFunc, boolType, 11);
    enter("ABS", ORB_SFunc, intType, 1);
    
    /* Procedures */
    enter("UNPK", ORB_SProc, noType, 72);
    enter("PACK", ORB_SProc, noType, 62);
    enter("NEW", ORB_SProc, noType, 51);
    enter("ASSERT", ORB_SProc, noType, 41);
    enter("EXCL", ORB_SProc, noType, 32);
    enter("INCL", ORB_SProc, noType, 22);
    enter("DEC", ORB_SProc, noType, 11);
    enter("INC", ORB_SProc, noType, 1);
    
    /* Types */
    enter("SET", ORB_Typ, setType, 0);
    enter("BOOLEAN", ORB_Typ, boolType, 0);
    enter("BYTE", ORB_Typ, byteType, 0);
    enter("CHAR", ORB_Typ, charType, 0);
    enter("LONGREAL", ORB_Typ, realType, 0);
    enter("REAL", ORB_Typ, realType, 0);
    enter("LONGINT", ORB_Typ, longType, 0);
    enter("INTEGER", ORB_Typ, intType, 0);
    
    topScope = NULL;
    OpenScope();
    topScope->next = systemScope;
    universe = topScope;
    
    /* Initialize "unsafe" pseudo-module SYSTEM */
    systemScope = NULL;
    
    /* Functions */
    enter("SIZE", ORB_SFunc, intType, 181);
    enter("ADR", ORB_SFunc, longType, 171);
    enter("VAL", ORB_SFunc, intType, 162);
    enter("BIT", ORB_SFunc, boolType, 142);

    /* Procedures */
    enter("COPY", ORB_SProc, noType, 123);
    enter("PUT", ORB_SProc, noType, 112);
    enter("GET", ORB_SProc, noType, 102);
}
