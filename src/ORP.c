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

// ORP.c - Stage 1: Headers and Basic Utility Functions
// Translated from ORP.Mod by N.Wirth

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <ctype.h>
#include <sys/stat.h>
#include "ORP.h"
#include "ORS.h"
#include "ORB.h"
#include "ORG.h"
#include "Texts.h"
#include "Oberon.h"

// Global variables
static INTEGER sym;
static LONGINT dc;
static INTEGER level, exno;
static BOOLEAN newSF;
static void (*expression)(ORG_Item *x);
static void (*Type)(ORB_Type **type);
static void (*FormalType)(ORB_Type **typ, INTEGER dim);
static ORS_Ident modid;
static PtrBase *pbsList;
static ORB_Object *dummy;
static Texts_Writer W;

// Forward declarations
static void expression0(ORG_Item *x);
static void Type0(ORB_Type **type);
static void FormalType0(ORB_Type **typ, INTEGER dim);
static void StatSequence(void);
static void ProcedureType(ORB_Type *ptype, LONGINT *parblksize);
static void Declarations(LONGINT *varsize, LONGINT parblksize);
static void ProcedureDecl(void);

// Basic utility functions
static void Check(INTEGER s, char *msg) {
    if (sym == s) {
        ORS_Get(&sym);
    } else {
        ORS_Mark(msg);
    }
}

static void qualident(ORB_Object **obj) {
    *obj = thisObj();
    ORS_Get(&sym);
    if (*obj == NULL) {
        ORS_Mark("undef");
        *obj = dummy;
    }
    if ((sym == ORS_period) && ((*obj)->class == ORB_Mod)) {
        ORS_Get(&sym);
        if (sym == ORS_ident) {
            *obj = thisimport(*obj);
            ORS_Get(&sym);
            if (*obj == NULL) {
                ORS_Mark("undef");
                *obj = dummy;
            }
        } else {
            ORS_Mark("identifier expected");
            *obj = dummy;
        }
    }
}

static void CheckBool(ORG_Item *x) {
    if (x->type->form != ORB_Bool) {
        ORS_Mark("not Boolean");
        x->type = boolType;
    }
}

static void CheckInt(ORG_Item *x) {
    if (x->type->form != ORB_Int) {
        ORS_Mark("not Integer");
        x->type = intType;
    }
}

static void CheckReal(ORG_Item *x) {
    if (x->type->form != ORB_Real) {
        ORS_Mark("not Real");
        x->type = realType;
    }
}

static void CheckSet(ORG_Item *x) {
    if (x->type->form != ORB_Set) {
        ORS_Mark("not Set");
        x->type = setType;
    }
}

static void CheckSetVal(ORG_Item *x) {
    if (x->type->form != ORB_Int) {
        ORS_Mark("not Int");
        x->type = setType;
    } else if (x->mode == ORB_Const) {
        if ((x->a < 0) || (x->a >= 32)) {   /* SET is 32 bits in this dialect */
            ORS_Mark("invalid set");
        }
    }
}

static void CheckConst(ORG_Item *x) {
    if (x->mode != ORB_Const) {
        ORS_Mark("not a constant");
        x->mode = ORB_Const;
    }
}

static void CheckReadOnly(ORG_Item *x) {
    if (x->rdo) {
        ORS_Mark("read-only");
    }
}

static void CheckExport(BOOLEAN *expo) {
    if (sym == ORS_times) {
        *expo = TRUE;
        ORS_Get(&sym);
        if (level != 0) {
            ORS_Mark("remove asterisk");
        }
    } else {
        *expo = FALSE;
    }
}

static BOOLEAN IsExtension(ORB_Type *t0, ORB_Type *t1) {
    return (t0 == t1) || ((t1 != NULL) && IsExtension(t0, t1->base));
}

/* ORP.c - Parser Implementation - Stage 2: Expression Parsing */

// Stage 2: Expression Parsing Helper Functions

static void TypeTest(ORG_Item *x, ORB_Type *T, BOOLEAN guard) {
    ORB_Type *xt = x->type;
    
    if ((T->form == xt->form) && 
        ((T->form == ORB_Pointer) || 
         ((T->form == ORB_Record) && (x->mode == ORB_Par)))) {
        
        while ((xt != T) && (xt != NULL)) {
            xt = xt->base;
        }
        
        if (xt != T) {
            xt = x->type;
            if (xt->form == ORB_Pointer) {
                if (IsExtension(xt->base, T->base)) {
                    ORG_TypeTest(x, T->base, FALSE, guard);
                    x->type = T;
                } else {
                    ORS_Mark("not an extension");
                }
            } else if ((xt->form == ORB_Record) && (x->mode == ORB_Par)) {
                if (IsExtension(xt, T)) {
                    ORG_TypeTest(x, T, TRUE, guard);
                    x->type = T;
                } else {
                    ORS_Mark("not an extension");
                }
            } else {
                ORS_Mark("incompatible types");
            }
        } else if (!guard) {
            ORG_TypeTest(x, NULL, FALSE, FALSE);
        }
    } else {
        ORS_Mark("type mismatch");
    }
    
    if (!guard) {
        x->type = boolType;
    }
}

static void selector(ORG_Item *x) {
    ORG_Item y;
    ORB_Object *obj;
    
    while ((sym == ORS_lbrak) || (sym == ORS_period) || (sym == ORS_arrow) ||
           ((sym == ORS_lparen) && 
            ((x->type->form == ORB_Record) || (x->type->form == ORB_Pointer)))) {
        
        if (sym == ORS_lbrak) {
            do {
                ORS_Get(&sym);
                expression(&y);
                if (x->type->form == ORB_Array) {
                    CheckInt(&y);
                    ORG_Index(x, &y);
                    x->type = x->type->base;
                } else {
                    ORS_Mark("not an array");
                }
            } while (sym == ORS_comma);
            Check(ORS_rbrak, "no ]");
            
        } else if (sym == ORS_period) {
            ORS_Get(&sym);
            if (sym == ORS_ident) {
                if (x->type->form == ORB_Pointer) {
                    ORG_DeRef(x);
                    x->type = x->type->base;
                }
                if (x->type->form == ORB_Record) {
                    obj = thisfield(x->type);
                    ORS_Get(&sym);
                    if (obj != NULL) {
                        ORG_Field(x, obj);
                        x->type = obj->type;
                    } else {
                        ORS_Mark("undef");
                    }
                } else {
                    ORS_Mark("not a record");
                }
            } else {
                ORS_Mark("ident?");
            }
            
        } else if (sym == ORS_arrow) {
            ORS_Get(&sym);
            if (x->type->form == ORB_Pointer) {
                ORG_DeRef(x);
                x->type = x->type->base;
            } else {
                ORS_Mark("not a pointer");
            }
            
        } else if ((sym == ORS_lparen) && 
                   ((x->type->form == ORB_Record) || (x->type->form == ORB_Pointer))) {
            ORS_Get(&sym);
            if (sym == ORS_ident) {
                qualident(&obj);
                if (obj->class ==ORB_Typ) {
                    TypeTest(x, obj->type, TRUE);
                } else {
                    ORS_Mark("guard type expected");
                }
            } else {
                ORS_Mark("not an identifier");
            }
            Check(ORS_rparen, " ) missing");
        }
    }
}

static BOOLEAN EqualSignatures(ORB_Type *t0, ORB_Type *t1) {
    ORB_Object *p0, *p1;
    BOOLEAN com = TRUE;
    
    if ((t0->base == t1->base) && (t0->nofpar == t1->nofpar)) {
        p0 = t0->dsc;
        p1 = t1->dsc;
        while (p0 != NULL) {
            if ((p0->class == p1->class) && (p0->rdo == p1->rdo) &&
                ((p0->type == p1->type) ||
                 ((p0->type->form == ORB_Array) && (p1->type->form == ORB_Array) &&
                  (p0->type->len == p1->type->len) && (p0->type->base == p1->type->base)) ||
                 ((p0->type->form == ORB_Proc) && (p1->type->form == ORB_Proc) &&
                  EqualSignatures(p0->type, p1->type)))) {
                p0 = p0->next;
                p1 = p1->next;
            } else {
                p0 = NULL;
                com = FALSE;
            }
        }
    } else {
        com = FALSE;
    }
    return com;
}

static BOOLEAN CompTypes(ORB_Type *t0, ORB_Type *t1, BOOLEAN varpar) {
    return (t0 == t1) ||
           ((t0->form == ORB_Array) && (t1->form == ORB_Array) && 
            (t0->base == t1->base) && (t0->len == t1->len)) ||
           ((t0->form == ORB_Record) && (t1->form == ORB_Record) && 
            IsExtension(t0, t1)) ||
           (!varpar &&
            (((t0->form == ORB_Pointer) && (t1->form == ORB_Pointer) && 
              IsExtension(t0->base, t1->base)) ||
             ((t0->form == ORB_Proc) && (t1->form == ORB_Proc) && 
              EqualSignatures(t0, t1)) ||
             (((t0->form == ORB_Pointer) || (t0->form == ORB_Proc)) && 
              (t1->form == ORB_NilTyp))));
}

/* ORP.c - Parser Implementation - Stage 3: Statement Parsing */

// Stage 3: Parameter Handling and Standard Functions

static void Parameter(ORB_Object *par) {
    ORG_Item x;
    BOOLEAN varpar;
    
    expression(&x);
    if (par != NULL) {
        varpar = (par->class == ORB_Par);
        if (CompTypes(par->type, x.type, varpar)) {
            if (!varpar) {
                ORG_ValueParam(&x);
            } else {
                if (!par->rdo) {
                    CheckReadOnly(&x);
                }
                ORG_VarParam(&x, par->type);
            }
        } else if ((x.type->form == ORB_Array) && (par->type->form == ORB_Array) &&
                   (x.type->base == par->type->base) && (par->type->len < 0)) {
            if (!par->rdo) {
                CheckReadOnly(&x);
            }
            ORG_OpenArrayParam(&x);
        } else if ((x.type->form == ORB_String) &&
                   (par->type->form == ORB_Array) && (par->type->base->form == ORB_Char) &&
                   (par->type->len < 0)) {
            ORG_StringParam(&x);
        } else if (!varpar && (par->type->form == ORB_Int) && (x.type->form == ORB_Int)) {
            ORG_ValueParam(&x);  // BYTE
        } else if ((x.type->form == ORB_String) && (x.b == 2) && 
                   (par->class == ORB_Var) && (par->type->form == ORB_Char)) {
            ORG_StrToChar(&x);
            ORG_ValueParam(&x);
        } else if ((par->type->form == ORB_Array) && (par->type->base == byteType) &&
                   (par->type->len >= 0) && (par->type->size == x.type->size)) {
            ORG_VarParam(&x, par->type);
        } else {
            ORS_Mark("incompatible parameters");
        }
    }
}

static void ParamList(ORG_Item *x) {
    INTEGER n = 0;
    ORB_Object *par = x->type->dsc;
    
    if (sym != ORS_rparen) {
        Parameter(par);
        n = 1;
        while (sym <= ORS_comma) {
            Check(ORS_comma, "comma?");
            if (par != NULL) {
                par = par->next;
            }
            n++;
            Parameter(par);
        }
        Check(ORS_rparen, ") missing");
    } else {
        ORS_Get(&sym);
    }
    
    if (n < x->type->nofpar) {
        ORS_Mark("too few params");
    } else if (n > x->type->nofpar) {
        ORS_Mark("too many params");
    }
}

static void StandFunc(ORG_Item *x, LONGINT fct, ORB_Type *restyp) {
    ORG_Item y;
    LONGINT n, npar;
    
    Check(ORS_lparen, "no (");
    npar = fct % 10;
    fct = fct / 10;
    expression(x);
    n = 1;
    
    while (sym == ORS_comma) {
        ORS_Get(&sym);
        expression(&y);
        n++;
    }
    Check(ORS_rparen, "no )");
    
    if (n == npar) {
        if (fct == 0) {  // ABS
            if ((x->type->form == ORB_Int) || (x->type->form == ORB_Real)) {
                ORG_Abs(x);
                restyp = x->type;
            } else {
                ORS_Mark("bad type");
            }
        } else if (fct == 1) {  // ODD
            CheckInt(x);
            ORG_Odd(x);
        } else if (fct == 2) {  // FLOOR
            CheckReal(x);
            ORG_Floor(x);
        } else if (fct == 3) {  // FLT
            CheckInt(x);
            ORG_Float(x);
        } else if (fct == 4) {  // ORD
            if (x->type->form <= ORB_Proc) {
                ORG_Ord(x);
            } else if ((x->type->form == ORB_String) && (x->b == 2)) {
                ORG_StrToChar(x);
            } else {
                ORS_Mark("bad type");
            }
        } else if (fct == 5) {  // CHR
            CheckInt(x);
            ORG_Ord(x);
        } else if (fct == 6) {  // LEN
            if (x->type->form == ORB_Array) {
                ORG_Len(x);
            } else {
                ORS_Mark("not an array");
            }
        } else if ((fct >= 7) && (fct <= 9)) {  // AND, EOR, ORA
            CheckInt(&y);
            if ((x->type->form == ORB_Int) || (x->type->form == ORB_Set)) {
                ORG_Bitwise(fct - 7, x, &y);
                restyp = x->type;
            } else {
                ORS_Mark("bad type");
            }
        } else if ((fct >= 10) && (fct <= 12)) {  // ASL, LSR, ROL
            CheckInt(&y);
            if ((x->type->form == ORB_Int) || (x->type->form == ORB_Set)) {
                ORG_Shift(fct - 10, x, &y);
                restyp = x->type;
            } else {
                ORS_Mark("bad type");
            }
        } else if (fct == 13) {  // UML
            ORG_UML(x, &y);
        } else if (fct == 14) {  // BIT
            CheckInt(x);
            CheckInt(&y);
            ORG_Bit(x, &y);
        } else if (fct == 16) {  // VAL
            if ((x->mode ==ORB_Typ) && (x->type->size <= y.type->size)) {
                restyp = x->type;
                *x = y;
            } else {
                ORS_Mark("casting not allowed");
            }
        } else if (fct == 17) {  // ADR
            ORG_Adr(x);
        } else if (fct == 18) {  // SIZE
            if (x->mode ==ORB_Typ) {
                ORG_MakeConstItem(x, intType, x->type->size);
            } else {
                ORS_Mark("must be a type");
            }
        }
        x->type = restyp;
    } else {
        ORS_Mark("wrong nof params");
    }
}

static void element(ORG_Item *x) {
    ORG_Item y;
    
    expression(x);
    CheckSetVal(x);
    if (sym == ORS_upto) {
        ORS_Get(&sym);
        expression(&y);
        CheckSetVal(&y);
        ORG_Set(x, &y);
    } else {
        ORG_Singleton(x);
    }
    x->type = setType;
}

static void set(ORG_Item *x) {
    ORG_Item y;
    
    if (sym >= ORS_if) {
        if (sym != ORS_rbrace) {
            ORS_Mark(" } missing");
        }
        ORG_MakeConstItem(x, setType, 0);  // empty set
    } else {
        element(x);
        while ((sym < ORS_rparen) || (sym > ORS_rbrace)) {
            if (sym == ORS_comma) {
                ORS_Get(&sym);
            } else if (sym != ORS_rbrace) {
                ORS_Mark("missing comma");
            }
            element(&y);
            ORG_SetOp(ORS_plus, x, &y);
        }
    }
}

/* ORP.c - Parser Implementation - Stage 4: Type and Declaration Parsing */

// Stage 4: Expression Parsing Implementation

static void factor(ORG_Item *x) {
    ORB_Object *obj;
    LONGINT rx;
    
    // sync
    if ((sym < ORS_char) || (sym > ORS_ident)) {
        ORS_Mark("expression expected");
        do {
            ORS_Get(&sym);
        } while (((sym < ORS_char) || (sym > ORS_for)) && (sym < ORS_then));
    }
    
    if (sym == ORS_ident) {
        qualident(&obj);
        if (obj->class == ORB_SFunc) {
            StandFunc(x, obj->val, obj->type);
        } else {
            ORG_MakeItem(x, obj, level);
            selector(x);
            if (sym == ORS_lparen) {
                ORS_Get(&sym);
                if ((x->type->form == ORB_Proc) && (x->type->base->form != ORB_NoTyp)) {
                    ORG_PrepCall(x, &rx);
                    ParamList(x);
                    ORG_Call(x, rx);
                    x->type = x->type->base;
                } else {
                    ORS_Mark("not a function");
                    ParamList(x);
                }
            }
        }
    } else if (sym == ORS_int) {
        ORG_MakeConstItem(x, intType, ORS_ival);
        ORS_Get(&sym);
    } else if (sym == ORS_real) {
        ORG_MakeRealItem(x, ORS_rval);
        ORS_Get(&sym);
    } else if (sym == ORS_char) {
        ORG_MakeConstItem(x, charType, ORS_ival);
        ORS_Get(&sym);
    } else if (sym == ORS_nil) {
        ORS_Get(&sym);
        ORG_MakeConstItem(x, nilType, 0);
    } else if (sym == ORS_string) {
        ORG_MakeStringItem(x, ORS_slen);
        ORS_Get(&sym);
    } else if (sym == ORS_lparen) {
        ORS_Get(&sym);
        expression(x);
        Check(ORS_rparen, "no )");
    } else if (sym == ORS_lbrace) {
        ORS_Get(&sym);
        set(x);
        Check(ORS_rbrace, "no }");
    } else if (sym == ORS_not) {
        ORS_Get(&sym);
        factor(x);
        CheckBool(x);
        ORG_Not(x);
    } else if (sym == ORS_false) {
        ORS_Get(&sym);
        ORG_MakeConstItem(x, boolType, 0);
    } else if (sym == ORS_true) {
        ORS_Get(&sym);
        ORG_MakeConstItem(x, boolType, 1);
    } else {
        ORS_Mark("not a factor");
        ORG_MakeConstItem(x, intType, 0);
    }
}

static void term(ORG_Item *x) {
    ORG_Item y;
    INTEGER op, f;
    
    factor(x);
    f = x->type->form;
    
    while ((sym >= ORS_times) && (sym <= ORS_and)) {
        op = sym;
        ORS_Get(&sym);
        
        if (op == ORS_times) {
            if (f == ORB_Int) {
                factor(&y);
                CheckInt(&y);
                ORG_MulOp(x, &y);
            } else if (f == ORB_Real) {
                factor(&y);
                CheckReal(&y);
                ORG_RealOp(op, x, &y);
            } else if (f == ORB_Set) {
                factor(&y);
                CheckSet(&y);
                ORG_SetOp(op, x, &y);
            } else {
                ORS_Mark("bad type");
            }
        } else if ((op == ORS_div) || (op == ORS_mod)) {
            CheckInt(x);
            factor(&y);
            CheckInt(&y);
            ORG_DivOp(op, x, &y);
        } else if (op == ORS_rdiv) {
            if (f == ORB_Real) {
                factor(&y);
                CheckReal(&y);
                ORG_RealOp(op, x, &y);
            } else if (f == ORB_Set) {
                factor(&y);
                CheckSet(&y);
                ORG_SetOp(op, x, &y);
            } else {
                ORS_Mark("bad type");
            }
        } else {  // op == and
            CheckBool(x);
            ORG_And1(x);
            factor(&y);
            CheckBool(&y);
            ORG_And2(x, &y);
        }
    }
}

static void SimpleExpression(ORG_Item *x) {
    ORG_Item y;
    INTEGER op;
    
    if (sym == ORS_minus) {
        ORS_Get(&sym);
        term(x);
        if ((x->type->form == ORB_Int) || (x->type->form == ORB_Real) || 
            (x->type->form == ORB_Set)) {
            ORG_Neg(x);
        } else {
            CheckInt(x);
        }
    } else if (sym == ORS_plus) {
        ORS_Get(&sym);
        term(x);
    } else {
        term(x);
    }
    
    while ((sym >= ORS_plus) && (sym <= ORS_or)) {
        op = sym;
        ORS_Get(&sym);
        
        if (op == ORS_or) {
            ORG_Or1(x);
            CheckBool(x);
            term(&y);
            CheckBool(&y);
            ORG_Or2(x, &y);
        } else if (x->type->form == ORB_Int) {
            term(&y);
            CheckInt(&y);
            ORG_AddOp(op, x, &y);
        } else if (x->type->form == ORB_Real) {
            term(&y);
            CheckReal(&y);
            ORG_RealOp(op, x, &y);
        } else {
            CheckSet(x);
            term(&y);
            CheckSet(&y);
            ORG_SetOp(op, x, &y);
        }
    }
}

static void expression0(ORG_Item *x) {
    ORG_Item y;
    ORB_Object *obj;
    INTEGER rel, xf, yf;
    
    SimpleExpression(x);
    
    if ((sym >= ORS_eql) && (sym <= ORS_gtr)) {
        rel = sym;
        ORS_Get(&sym);
        SimpleExpression(&y);
        xf = x->type->form;
        yf = y.type->form;
        
        if (x->type == y.type) {
            if ((xf == ORB_Char) || (xf == ORB_Int)) {
                ORG_IntRelation(rel, x, &y);
            } else if (xf == ORB_Real) {
                ORG_RealRelation(rel, x, &y);
            } else if ((xf == ORB_Set) || (xf == ORB_Pointer) || (xf == ORB_Proc) || 
                       (xf == ORB_NilTyp) || (xf == ORB_Bool)) {
                if (rel <= ORS_neq) {
                    ORG_IntRelation(rel, x, &y);
                } else {
                    ORS_Mark("only = or #");
                }
            } else if (((xf == ORB_Array) && (x->type->base->form == ORB_Char)) || 
                       (xf == ORB_String)) {
                ORG_StringRelation(rel, x, &y);
            } else {
                ORS_Mark("illegal comparison");
            }
        } else if (((xf == ORB_Pointer) || ((xf == ORB_Proc) && (yf == ORB_NilTyp))) ||
                   ((yf == ORB_Pointer) || ((yf == ORB_Proc) && (xf == ORB_NilTyp)))) {
            if (rel <= ORS_neq) {
                ORG_IntRelation(rel, x, &y);
            } else {
                ORS_Mark("only = or #");
            }
        } else if ((((xf == ORB_Pointer) && (yf == ORB_Pointer)) &&
					((IsExtension(x->type->base, y.type->base)) || 
                    (IsExtension(y.type->base, x->type->base)))) ||
                   ((xf == ORB_Proc) && (yf == ORB_Proc) && 
                    EqualSignatures(x->type, y.type))) {
            if (rel <= ORS_neq) {
                ORG_IntRelation(rel, x, &y);
            } else {
                ORS_Mark("only = or #");
            }
        } else if (((xf == ORB_Array) && (x->type->base->form == ORB_Char) &&
                    ((yf == ORB_String) || ((yf == ORB_Array) && 
                     (y.type->base->form == ORB_Char)))) ||
                   ((yf == ORB_Array) && (y.type->base->form == ORB_Char) && 
                    (xf == ORB_String))) {
            ORG_StringRelation(rel, x, &y);
        } else if ((xf == ORB_Char) && (yf == ORB_String) && (y.b == 2)) {
            ORG_StrToChar(&y);
            ORG_IntRelation(rel, x, &y);
        } else if ((yf == ORB_Char) && (xf == ORB_String) && (x->b == 2)) {
            ORG_StrToChar(x);
            ORG_IntRelation(rel, x, &y);
        } else if ((xf == ORB_Int) && (yf == ORB_Int)) {
            ORG_IntRelation(rel, x, &y);  // BYTE
        } else {
            ORS_Mark("illegal comparison");
        }
        x->type = boolType;
    } else if (sym == ORS_in) {
        ORS_Get(&sym);
        CheckInt(x);
        SimpleExpression(&y);
        CheckSet(&y);
        ORG_In(x, &y);
        x->type = boolType;
    } else if (sym == ORS_is) {
        ORS_Get(&sym);
        qualident(&obj);
        TypeTest(x, obj->type, FALSE);
        x->type = boolType;
    }
}

// ORP Stage 5 - Main Procedures and Module Functions

// Stage 5: Statements, Declarations, and Main Functions

static void StandProc(LONGINT pno) {
    LONGINT nap, npar;
    ORG_Item x, y, z;
    
    Check(ORS_lparen, "no (");
    npar = pno % 10;
    pno = pno / 10;
    expression(&x);
    nap = 1;
    
    if (sym == ORS_comma) {
        ORS_Get(&sym);
        expression(&y);
        nap = 2;
        z.type = noType;
        while (sym == ORS_comma) {
            ORS_Get(&sym);
            expression(&z);
            nap++;
        }
    } else {
        y.type = noType;
    }
    Check(ORS_rparen, "no )");
    
    if ((npar == nap) || ((pno == 0) || (pno == 1))) {
	  if ((pno == 0) || (pno == 1)) {  // INC, DEC
		CheckInt(&x);
		CheckReadOnly(&x);
		if (y.type != noType) {
		  CheckInt(&y);
		} else {
		  /* No step given → default to 1 of the variable's int width. */
		  ORG_MakeConstItem(&y, x.type, 1);
		}
		ORG_Increment(pno, &x, &y);
	  } else if ((pno == 2) || (pno == 3)) {  // INCL, EXCL
		CheckSet(&x);
		CheckReadOnly(&x);
		CheckInt(&y);
		ORG_Include(pno - 2, &x, &y);
	  } else if (pno == 4) {  // ASSERT
		CheckBool(&x);
		ORG_Assert(&x);
	  } else if (pno == 5) {  // NEW
		CheckReadOnly(&x);
		if ((x.type->form == ORB_Pointer) && (x.type->base->form == ORB_Record)) {
		  ORG_New(&x);
		} else {
		  ORS_Mark("not a pointer to record");
		}
	  } else if (pno == 6) {  // PACK
		CheckReal(&x);
		CheckInt(&y);
		CheckReadOnly(&x);
		ORG_Pack(&x, &y);
	  } else if (pno == 7) {  // UNPK
		CheckReal(&x);
		CheckInt(&y);
		CheckReadOnly(&x);
		ORG_Unpk(&x, &y);
	  } else if (pno == 10) {  // GET(addr, VAR var)
		CheckInt(&x);
		ORG_Get(&x, &y);
	  } else if (pno == 11) {  // PUT(addr, val)
		CheckInt(&x);
		ORG_Put(&x, &y);
	  } else if (pno == 12) {  // COPY
		CheckInt(&x);
		CheckInt(&y);
		CheckInt(&z);
		ORG_Copy(&x, &y, &z);
	  }
	} else {
	  ORS_Mark("wrong nof parameters");
    }
}

// TypeCase procedure
void TypeCase(ORB_Object *obj, ORG_Item *x) {
  ORB_Object *typobj;
  if (sym == ORS_ident) {
	qualident(&typobj);
	ORG_MakeItem(x, obj, level);
	if (typobj->class !=ORB_Typ) {
	  ORS_Mark("not a type");
	}
	TypeTest(x, typobj->type, FALSE);
	obj->type = typobj->type;
	ORG_CFJump(x);
	Check(ORS_colon, ": expected");
	StatSequence();
  } else {
	ORG_CFJump(x);
	ORS_Mark("type id expected");
  }
}
    
// SkipCase procedure
void SkipCase(void) {
  while (sym != ORS_colon) {
	ORS_Get(&sym);
  }
  ORS_Get(&sym);
  StatSequence();
}

// Numeric CASE helpers

static LONGINT parseCaseLabel(void) {
  ORB_Object *obj;
  LONGINT val = 0;
  if (sym == ORS_int) {
    val = ORS_ival;
    ORS_Get(&sym);
  } else if (sym == ORS_string && ORS_slen == 2) {
    val = ORS_str[0];
    ORS_Get(&sym);
  } else if (sym == ORS_ident) {
    qualident(&obj);
    if (obj->class == ORB_Const) {
      val = obj->val;
    } else {
      ORS_Mark("not a constant");
    }
  } else {
    ORS_Mark("case label expected");
  }
  return val;
}

static void CaseLabelRange(ORB_Object *caseObj, LONGINT *hitChain) {
  ORG_Item cx;
  LONGINT lo, hi;
  lo = parseCaseLabel();
  if (sym == ORS_upto) {
    ORS_Get(&sym);
    hi = parseCaseLabel();
    ORG_MakeItem(&cx, caseObj, level);
    ORG_CaseRange(&cx, lo, hi, hitChain);
  } else {
    ORG_MakeItem(&cx, caseObj, level);
    ORG_CaseLabel(&cx, lo, hitChain);
  }
}

static void CaseLabelList(ORB_Object *caseObj, LONGINT *hitChain) {
  CaseLabelRange(caseObj, hitChain);
  while (sym == ORS_comma) {
    ORS_Get(&sym);
    CaseLabelRange(caseObj, hitChain);
  }
}

static void NumericCaseArm(ORB_Object *caseObj, LONGINT *endChain) {
  LONGINT hitChain = 0;
  LONGINT missLink = 0;
  CaseLabelList(caseObj, &hitChain);
  ORG_FJump(&missLink);      // skip body if no label matched
  ORG_FixLink(hitChain);     // matched labels land here
  Check(ORS_colon, ": expected");
  StatSequence();
  ORG_FJump(endChain);       // jump to end of CASE
  ORG_FixOne(missLink);      // no-match continues to next arm
}

static void StatSequence(void) {
    ORB_Object *obj;
    ORB_Type *orgtype;
    ORG_Item x, y, z, w;
    LONGINT L0, L1, rx;
    
    do {
        obj = NULL;
        
        // sync
        if (!((sym >= ORS_ident) && (sym <= ORS_for)) && (sym < ORS_semicolon)) {
            ORS_Mark("statement expected");
            do {
                ORS_Get(&sym);
            } while (sym < ORS_ident);
        }
        
        if (sym == ORS_ident) {
            qualident(&obj);
            ORG_MakeItem(&x, obj, level);
            if (x.mode == ORB_SProc) {
                StandProc(obj->val);
            } else {
                selector(&x);
                if (sym == ORS_becomes) {  // assignment
                    ORS_Get(&sym);
                    CheckReadOnly(&x);
                    expression(&y);
                    if (CompTypes(x.type, y.type, FALSE)) {
                        if ((x.type->form <= ORB_Pointer) || (x.type->form == ORB_Proc)) {
                            ORG_Store(&x, &y);
                        } else {
                            ORG_StoreStruct(&x, &y);
                        }
                    } else if ((x.type->form == ORB_Array) && (y.type->form == ORB_Array) &&
                               (x.type->base == y.type->base) && (y.type->len < 0)) {
                        ORG_StoreStruct(&x, &y);
                    } else if ((x.type->form == ORB_Array) && (x.type->base->form == ORB_Char) &&
                               (y.type->form == ORB_String)) {
                        ORG_CopyString(&x, &y);
                    } else if ((x.type->form == ORB_Int) && (y.type->form == ORB_Int)) {
                        ORG_Store(&x, &y);  // BYTE
                    } else if ((x.type->form == ORB_Char) && (y.type->form == ORB_String) &&
                               (y.b == 2)) {
                        ORG_StrToChar(&y);
                        ORG_Store(&x, &y);
                    } else {
                        ORS_Mark("illegal assignment");
                    }
                } else if (sym == ORS_eql) {
                    ORS_Mark("should be :=");
                    ORS_Get(&sym);
                    expression(&y);
                } else if (sym == ORS_lparen) {  // procedure call
                    ORS_Get(&sym);
                    if ((x.type->form == ORB_Proc) && (x.type->base->form == ORB_NoTyp)) {
                        ORG_PrepCall(&x, &rx);
                        ParamList(&x);
                        ORG_Call(&x, rx);
                    } else {
                        ORS_Mark("not a procedure");
                        ParamList(&x);
                    }
                } else if (x.type->form == ORB_Proc) {  // procedure call without parameters
                    if (x.type->nofpar > 0) {
                        ORS_Mark("missing parameters");
                    }
                    if (x.type->base->form == ORB_NoTyp) {
                        ORG_PrepCall(&x, &rx);
                        ORG_Call(&x, rx);
                    } else {
                        ORS_Mark("not a procedure");
                    }
                } else if (x.mode ==ORB_Typ) {
                    ORS_Mark("illegal assignment");
                } else {
                    ORS_Mark("not a procedure");
                }
            }
        } else if (sym == ORS_if) {
            ORS_Get(&sym);
            expression(&x);
            CheckBool(&x);
            ORG_CFJump(&x);
            Check(ORS_then, "no THEN");
            StatSequence();
            L0 = 0;
            while (sym == ORS_elsif) {
                ORS_Get(&sym);
                ORG_FJump(&L0);
                ORG_Fixup(&x);
                expression(&x);
                CheckBool(&x);
                ORG_CFJump(&x);
                Check(ORS_then, "no THEN");
                StatSequence();
            }
            if (sym == ORS_else) {
                ORS_Get(&sym);
                ORG_FJump(&L0);
                ORG_Fixup(&x);
                StatSequence();
            } else {
                ORG_Fixup(&x);
            }
            ORG_FixLink(L0);
            Check(ORS_end, "no END");
        } else if (sym == ORS_while) {
            ORS_Get(&sym);
            L0 = ORG_Here();
            expression(&x);
            CheckBool(&x);
            ORG_CFJump(&x);
            Check(ORS_do, "no DO");
            StatSequence();
            ORG_BJump(L0);
            while (sym == ORS_elsif) {
                ORS_Get(&sym);
                ORG_Fixup(&x);
                expression(&x);
                CheckBool(&x);
                ORG_CFJump(&x);
                Check(ORS_do, "no DO");
                StatSequence();
                ORG_BJump(L0);
            }
            ORG_Fixup(&x);
            Check(ORS_end, "no END");
        } else if (sym == ORS_repeat) {
            ORS_Get(&sym);
            L0 = ORG_Here();
            StatSequence();
            if (sym == ORS_until) {
                ORS_Get(&sym);
                expression(&x);
                CheckBool(&x);
                ORG_CBJump(&x, L0);
            } else {
                ORS_Mark("missing UNTIL");
            }
        } else if (sym == ORS_for) {
            ORS_Get(&sym);
            if (sym == ORS_ident) {
                qualident(&obj);
                ORG_MakeItem(&x, obj, level);
                CheckInt(&x);
                CheckReadOnly(&x);
                if (sym == ORS_becomes) {
                    ORS_Get(&sym);
                    expression(&y);
                    CheckInt(&y);
                    ORG_For0(&x, &y);
                    L0 = ORG_Here();
                    Check(ORS_to, "no TO");
                    expression(&z);
                    CheckInt(&z);
                    obj->rdo = TRUE;
                    if (sym == ORS_by) {
                        ORS_Get(&sym);
                        expression(&w);
                        CheckConst(&w);
                        CheckInt(&w);
                    } else {
                        ORG_MakeConstItem(&w, intType, 1);
                    }
                    Check(ORS_do, "no DO");
                    ORG_For1(&x, &y, &z, &w, &L1);
                    StatSequence();
                    Check(ORS_end, "no END");
                    ORG_For2(&x, &y, &w);
                    ORG_BJump(L0);
                    ORG_FixLink(L1);
                    obj->rdo = FALSE;
                } else {
                    ORS_Mark(":= expected");
                }
            } else {
                ORS_Mark("identifier expected");
            }
        } else if (sym == ORS_case) {
            ORS_Get(&sym);
            if (sym == ORS_ident) {
                qualident(&obj);
                orgtype = obj->type;
                if ((orgtype->form == ORB_Pointer) ||
                    ((orgtype->form == ORB_Record) && (obj->class == ORB_Par))) {
                    Check(ORS_of, "OF expected");
                    TypeCase(obj, &x);
                    L0 = 0;
                    while (sym == ORS_bar) {
                        ORS_Get(&sym);
                        ORG_FJump(&L0);
                        ORG_Fixup(&x);
                        obj->type = orgtype;
                        TypeCase(obj, &x);
                    }
                    ORG_Fixup(&x);
                    ORG_FixLink(L0);
                    obj->type = orgtype;
                } else if (orgtype->form == ORB_Int || orgtype->form == ORB_Char) {
                    Check(ORS_of, "OF expected");
                    L0 = 0;
                    NumericCaseArm(obj, &L0);
                    while (sym == ORS_bar) {
                        ORS_Get(&sym);
                        NumericCaseArm(obj, &L0);
                    }
                    if (sym == ORS_else) {
                        ORS_Get(&sym);
                        StatSequence();
                    }
                    ORG_FixLink(L0);
                } else {
                    ORS_Mark("invalid case type");
                    Check(ORS_of, "OF expected");
                    SkipCase();
                    while (sym == ORS_bar) {
                        SkipCase();
                    }
                }
            } else {
                ORS_Mark("ident expected");
            }
            Check(ORS_end, "no END");
        }
        
        ORG_CheckRegs();
        if (sym == ORS_semicolon) {
            ORS_Get(&sym);
        } else if (sym < ORS_semicolon) {
            ORS_Mark("missing semicolon?");
            ORS_Get(&sym);  // Advance past problematic symbol to prevent infinite loop
        }
    } while (sym <= ORS_semicolon);
}

static void IdentList(INTEGER class, ORB_Object **first) {
    ORB_Object *obj;
    
    if (sym == ORS_ident) {
        NewObj(first, ORS_id, class);
        ORS_Get(&sym);
        CheckExport(&(*first)->expo);
        while (sym == ORS_comma) {
            ORS_Get(&sym);
            if (sym == ORS_ident) {
                NewObj(&obj, ORS_id, class);
                ORS_Get(&sym);
                CheckExport(&obj->expo);
            } else {
                ORS_Mark("ident?");
            }
        }
        if (sym == ORS_colon) {
            ORS_Get(&sym);
        } else {
            ORS_Mark(":?");
        }
    } else {
        *first = NULL;
    }
}

static void ArrayType(ORB_Type **type) {
    ORG_Item x;
    ORB_Type *typ;
    LONGINT len;
    
    typ = (ORB_Type*)calloc(1, sizeof(ORB_Type));
    typ->form = ORB_NoTyp;
    expression(&x);
    
    if ((x.mode == ORB_Const) && (x.type->form == ORB_Int) && (x.a >= 0)) {
        len = x.a;
    } else {
        len = 1;
        ORS_Mark("not a valid length");
    }
    
    if (sym == ORS_of) {
        ORS_Get(&sym);
        Type(&typ->base);
        if ((typ->base->form == ORB_Array) && (typ->base->len < 0)) {
            ORS_Mark("dyn array not allowed");
        }
    } else if (sym == ORS_comma) {
        ORS_Get(&sym);
        ArrayType(&typ->base);
    } else {
        ORS_Mark("missing OF");
        typ->base = intType;
    }
    
    typ->size = len * typ->base->size;
    typ->form  = ORB_Array;
    typ->len = len;
    *type = typ;
}

static void RecordType(ORB_Type **type) {
    ORB_Object *obj, *obj0, *new_obj, *bot, *base;
    ORB_Type *typ, *tp;
    LONGINT offset, off, n;
    
    typ = (ORB_Type*)calloc(1, sizeof(ORB_Type));
    typ->form = ORB_NoTyp;
    typ->base = NULL;
    typ->mno = -level;
    typ->nofpar = 0;
    offset = 0;
    bot = NULL;
    
    if (sym == ORS_lparen) {
        ORS_Get(&sym);
        if (level != 0) {
            ORS_Mark("extension of local types not implemented");
        }
        if (sym == ORS_ident) {
            qualident(&base);
            if (base->class ==ORB_Typ) {
                if (base->type->form == ORB_Record) {
                    typ->base = base->type;
                } else {
                    typ->base = intType;
                    ORS_Mark("invalid extension");
                }
                typ->nofpar = typ->base->nofpar + 1;
                bot = typ->base->dsc;
                offset = typ->base->size;
            } else {
                ORS_Mark("type expected");
            }
        } else {
            ORS_Mark("ident expected");
        }
        Check(ORS_rparen, "no )");
    }
    
    while (sym == ORS_ident) {
        n = 0;
        obj = bot;
        while (sym == ORS_ident) {
            obj0 = obj;
            while ((obj0 != NULL) && (strcmp(obj0->name, ORS_id) != 0)) {
                obj0 = obj0->next;
            }
            if (obj0 != NULL) {
                ORS_Mark("mult def");
            }
            new_obj = (ORB_Object*)calloc(1, sizeof(ORB_Object));
            strcpy(new_obj->name, ORS_id);
            new_obj->class = ORB_Fld;
            new_obj->next = obj;
            obj = new_obj;
            n++;
            ORS_Get(&sym);
            CheckExport(&new_obj->expo);
            if ((sym != ORS_comma) && (sym != ORS_colon)) {
                ORS_Mark("comma expected");
            } else if (sym == ORS_comma) {
                ORS_Get(&sym);
            }
        }
        Check(ORS_colon, "colon expected");
        Type(&tp);
        if ((tp->form == ORB_Array) && (tp->len < 0)) {
            ORS_Mark("dyn array not allowed");
        }
        if (tp->size > 1) {
            offset = (offset + 1) / 2 * 2;
        }
        offset = offset + n * tp->size;
        off = offset;
        obj0 = obj;
        while (obj0 != bot) {
            obj0->type = tp;
            obj0->lev = 0;
            off = off - tp->size;
            obj0->val = off;
            obj0 = obj0->next;
        }
        bot = obj;
        if (sym == ORS_semicolon) {
            ORS_Get(&sym);
        } else if (sym != ORS_end) {
            ORS_Mark(" ; or END");
        }
    }
    
    typ->form = ORB_Record;
    typ->dsc = bot;
    typ->size = offset;
    *type = typ;
}

static void FPSection(LONGINT *adr, INTEGER *nofpar) {
    ORB_Object *obj, *first;
    ORB_Type *tp;
    LONGINT parsize;
    INTEGER cl;
    BOOLEAN rdo;
    
    if (sym == ORS_var) {
        ORS_Get(&sym);
        cl = ORB_Par;
    } else {
        cl = ORB_Var;
    }

    IdentList(cl, &first);
    FormalType(&tp, 0);

    rdo = FALSE;
    if ((cl == ORB_Var) && (tp->form >= ORB_Array)) {
        cl = ORB_Par;
        rdo = TRUE;  // Array/record value parameters promoted to ORB_Par, read-only
    }

    if ((tp->form == ORB_Array) && (tp->len < 0)) {
        parsize = 2 * WordSize;  // open-array descriptor: pointer + length
    } else if ((cl == ORB_Par) && (tp->form == ORB_Record)) {
        parsize = 2 * WordSize;  // VAR record: pointer + type-tag
    } else if (cl == ORB_Par) {
        parsize = WordSize;      // VAR / promoted value params: pointer-sized
    } else {
        parsize = tp->size;
    }
    
    obj = first;
    while (obj != NULL) {
        (*nofpar)++;
        obj->class = cl;
        obj->type = tp;
        obj->rdo = rdo;
        obj->lev = level;
        obj->val = *adr + 1;  // 65C816 stack relative addressing starts at 1 (stack frame allocated before JSR)
        *adr = *adr + parsize;
        obj = obj->next;
    }
    
    if (*adr >= 52) {
        ORS_Mark("too many parameters");
    }
}

static void ProcedureType(ORB_Type *ptype, LONGINT *parblksize) {
    ORB_Object *obj;
    LONGINT size;
    INTEGER nofpar;
    
    ptype->base = noType;
    size = *parblksize;
    nofpar = 0;
    ptype->dsc = NULL;
    
    if (sym == ORS_lparen) {
        ORS_Get(&sym);
        if (sym == ORS_rparen) {
            ORS_Get(&sym);
        } else {
            FPSection(&size, &nofpar);
            while (sym == ORS_semicolon) {
                ORS_Get(&sym);
                FPSection(&size, &nofpar);
            }
            Check(ORS_rparen, "no )");
        }
        
        if (sym == ORS_colon) {
            ORS_Get(&sym);
            if (sym == ORS_ident) {
                qualident(&obj);
                ptype->base = obj->type;
                if (!((obj->class ==ORB_Typ) && 
                      (((obj->type->form >= ORB_Byte) && (obj->type->form <= ORB_Pointer)) ||
                      (obj->type->form == ORB_Proc)))) {
                    ORS_Mark("illegal function type");
                }
            } else {
                ORS_Mark("type identifier expected");
            }
        }
    }
    
    ptype->nofpar = nofpar;
    *parblksize = size;
}

static void FormalType0(ORB_Type **typ, INTEGER dim) {
    ORB_Object *obj;
    LONGINT dmy;
    
    if (sym == ORS_ident) {
        qualident(&obj);
        if (obj->class ==ORB_Typ) {
            *typ = obj->type;
        } else {
            ORS_Mark("not a type");
            *typ = intType;
        }
    } else if (sym == ORS_array) {
        ORS_Get(&sym);
        Check(ORS_of, "OF ?");
        if (dim >= 1) {
            ORS_Mark("multi-dimensional open arrays not implemented");
        }
        *typ = (ORB_Type*)calloc(1, sizeof(ORB_Type));
        (*typ)->form = ORB_Array;
        (*typ)->len = -1;
        (*typ)->size = 2 * WordSize;  // open-array descriptor: pointer + length
        FormalType(&(*typ)->base, dim + 1);
    } else if (sym == ORS_procedure) {
        ORS_Get(&sym);
        OpenScope();
        *typ = (ORB_Type*)calloc(1, sizeof(ORB_Type));
        (*typ)->form = ORB_Proc;
        (*typ)->size = 4;
        dmy = 0;
        ProcedureType(*typ, &dmy);
        (*typ)->dsc = topScope->next;
        CloseScope();
    } else {
        ORS_Mark("identifier expected");
        *typ = noType;
    }
}

static void CheckRecLevel(INTEGER lev) {
    if (lev != 0) {
        ORS_Mark("ptr base must be global");
    }
}

static void Type0(ORB_Type **type) {
    LONGINT dmy;
    ORB_Object *obj;
    PtrBase *ptbase;
    BOOLEAN is_weak = FALSE;

    *type = intType;
    if ((sym != ORS_ident) && (sym < ORS_array) && (sym != ORS_weak)) {
        ORS_Mark("not a type");
        do {
            ORS_Get(&sym);
        } while ((sym != ORS_ident) && (sym < ORS_array) && (sym != ORS_weak));
    }

    /* Optional WEAK prefix: applies only to a following POINTER type. */
    if (sym == ORS_weak) {
        ORS_Get(&sym);
        is_weak = TRUE;
        if (sym != ORS_pointer) {
            ORS_Mark("POINTER expected after WEAK");
        }
    }
    
    if (sym == ORS_ident) {
        qualident(&obj);
        if (obj->class ==ORB_Typ) {
            if ((obj->type != NULL) && (obj->type->form != ORB_NoTyp)) {
                *type = obj->type;
            }
        } else {
            ORS_Mark("not a type or undefined");
        }
    } else if (sym == ORS_array) {
        ORS_Get(&sym);
        ArrayType(type);
    } else if (sym == ORS_record) {
        ORS_Get(&sym);
        RecordType(type);
        Check(ORS_end, "no END");
    } else if (sym == ORS_pointer) {
        ORS_Get(&sym);
        Check(ORS_to, "no TO");
        *type = (ORB_Type*)calloc(1, sizeof(ORB_Type));
        (*type)->form = ORB_Pointer;
        (*type)->size = 4;
        (*type)->base = intType;
        (*type)->weak = is_weak;

        if (sym == ORS_ident) {
            obj = thisObj();
            if (obj != NULL) {
                if ((obj->class ==ORB_Typ) &&
                    ((obj->type->form == ORB_Record) || (obj->type->form == ORB_NoTyp))) {
                    CheckRecLevel(obj->lev);
                    (*type)->base = obj->type;
                } else if (obj->class == ORB_Mod) {
                    ORS_Mark("external base type not implemented");
                } else {
                    ORS_Mark("no valid base type");
                }
            } else {
                CheckRecLevel(level);
                ptbase = (PtrBase*)malloc(sizeof(PtrBase));
                strcpy(ptbase->name, ORS_id);
                ptbase->type = *type;
                ptbase->next = pbsList;
                pbsList = ptbase;
            }
            ORS_Get(&sym);
        } else {
            Type(type);
            if (((*type)->base->form != ORB_Record) || ((*type)->base->typobj == NULL)) {
                ORS_Mark("must point to named record");
            }
            CheckRecLevel(level);
        }
    } else if (sym == ORS_procedure) {
        ORS_Get(&sym);
        OpenScope();
        *type = (ORB_Type*)calloc(1, sizeof(ORB_Type));
        (*type)->form = ORB_Proc;
        (*type)->size = 4;
        dmy = 0;
        ProcedureType(*type, &dmy);
        (*type)->dsc = topScope->next;
        CloseScope();
    } else {
        ORS_Mark("illegal type");
    }
}

static void Declarations(LONGINT *varsize, LONGINT parblksize) {
    ORB_Object *obj, *first;
    ORG_Item x;
    ORB_Type *tp;
    PtrBase *ptbase;
    BOOLEAN expo;
    ORS_Ident id;
    
    pbsList = NULL;
    if ((sym < ORS_const) && (sym != ORS_end) && (sym != ORS_return)) {
        ORS_Mark("declaration?");
        do {
            ORS_Get(&sym);
        } while ((sym < ORS_const) && (sym != ORS_end) && (sym != ORS_return));
    }
    
    if (sym == ORS_const) {
        ORS_Get(&sym);
        while (sym == ORS_ident) {
            strcpy(id, ORS_id);
            ORS_Get(&sym);
            CheckExport(&expo);
            if (sym == ORS_eql) {
                ORS_Get(&sym);
            } else {
                ORS_Mark("= ?");
            }
            if (sym == ORS_array) {
                // Structured array constant: ARRAY OF type { val, val, ... }
                ORB_Object *typobj;
                ORB_Type *basetyp, *arrtyp;
                LONGINT start, count, val;
                ORS_Get(&sym);
                Check(ORS_of, "OF expected");
                if (sym == ORS_ident) {
                    qualident(&typobj);
                    if (typobj->class == ORB_Typ) {
                        basetyp = typobj->type;
                    } else {
                        ORS_Mark("not a type");
                        basetyp = intType;
                    }
                } else {
                    ORS_Mark("type expected");
                    basetyp = intType;
                }
                start = ORG_StrOffset();
                count = 0;
                if (sym == ORS_lbrace) {
                    ORS_Get(&sym);
                    while (sym != ORS_rbrace && sym != ORS_eof) {
                        expression(&x);
                        if (x.mode != ORB_Const) {
                            ORS_Mark("not a constant");
                            val = 0;
                        } else {
                            val = x.a;
                        }
                        if (basetyp->size == 1) {
                            ORG_PutByte(val);
                        } else if (basetyp->size == 2) {
                            ORG_PutByte(val & 0xFF);
                            ORG_PutByte((val >> 8) & 0xFF);
                        }
                        count++;
                        if (sym == ORS_comma) {
                            ORS_Get(&sym);
                        } else if (sym != ORS_rbrace) {
                            ORS_Mark(", or } expected");
                        }
                    }
                    Check(ORS_rbrace, "} expected");
                } else {
                    ORS_Mark("{ expected");
                }
                arrtyp = calloc(1, sizeof(ORB_Type));
                memset(arrtyp, 0, sizeof(ORB_Type));
                arrtyp->form = ORB_Array;
                arrtyp->base = basetyp;
                arrtyp->len = count;
                arrtyp->size = count * basetyp->size;
                NewObj(&obj, id, ORB_Const);
                obj->expo = expo;
                obj->val = start;
                obj->lev = count * basetyp->size;
                obj->type = arrtyp;
                if (expo) {
                    obj->exno = exno;
                    exno++;
                }
            } else if (sym == ORS_record) {
                // Structured record constant: RECORD ( TypeName ) { val, val, ... }
                ORB_Object *typobj, *fld;
                ORB_Type *rectyp;
                LONGINT start, val;
                ORS_Get(&sym);
                Check(ORS_lparen, "( expected");
                if (sym == ORS_ident) {
                    qualident(&typobj);
                    if (typobj->class == ORB_Typ && typobj->type->form == ORB_Record) {
                        rectyp = typobj->type;
                    } else {
                        ORS_Mark("not a record type");
                        rectyp = intType;
                    }
                } else {
                    ORS_Mark("type expected");
                    rectyp = intType;
                }
                Check(ORS_rparen, ") expected");
                start = ORG_StrOffset();
                if (sym == ORS_lbrace) {
                    ORS_Get(&sym);
                    fld = rectyp->dsc;
                    while (sym != ORS_rbrace && sym != ORS_eof) {
                        expression(&x);
                        if (x.mode != ORB_Const) {
                            ORS_Mark("not a constant");
                            val = 0;
                        } else {
                            val = x.a;
                        }
                        if (fld != NULL) {
                            if (fld->type->size == 1) {
                                ORG_PutByte(val);
                            } else if (fld->type->size == 2) {
                                ORG_PutByte(val & 0xFF);
                                ORG_PutByte((val >> 8) & 0xFF);
                            }
                            fld = fld->next;
                        } else {
                            ORS_Mark("too many values");
                        }
                        if (sym == ORS_comma) {
                            ORS_Get(&sym);
                        } else if (sym != ORS_rbrace) {
                            ORS_Mark(", or } expected");
                        }
                    }
                    Check(ORS_rbrace, "} expected");
                } else {
                    ORS_Mark("{ expected");
                }
                NewObj(&obj, id, ORB_Const);
                obj->expo = expo;
                obj->val = start;
                obj->lev = rectyp->size;
                obj->type = rectyp;
                if (expo) {
                    obj->exno = exno;
                    exno++;
                }
            } else {
                expression(&x);
                if ((x.type->form == ORB_String) && (x.b == 2)) {
                    ORG_StrToChar(&x);
                }
                NewObj(&obj, id, ORB_Const);
                obj->expo = expo;
                if (x.mode == ORB_Const) {
                    obj->val = x.a;
                    obj->lev = x.b;
                    obj->type = x.type;
                } else {
                    ORS_Mark("expression not constant");
                    obj->type = intType;
                }
            }
            Check(ORS_semicolon, "; missing");
        }
    }
    
    if (sym == ORS_type) {
        ORS_Get(&sym);
        while (sym == ORS_ident) {
            strcpy(id, ORS_id);
            ORS_Get(&sym);
            CheckExport(&expo);
            if (sym == ORS_eql) {
                ORS_Get(&sym);
            } else {
                ORS_Mark("=?");
            }
            Type(&tp);
            NewObj(&obj, id,ORB_Typ);
            obj->type = tp;
            obj->expo = expo;
            obj->lev = level;
            if (tp->typobj == NULL) {
                tp->typobj = obj;
            }
            if (expo && (obj->type->form == ORB_Record)) {
                obj->exno = exno;
                exno++;
            } else {
                obj->exno = 0;
            }
            if (tp->form == ORB_Record) {
                ptbase = pbsList;
                while (ptbase != NULL) {
                    if (strcmp(obj->name, ptbase->name) == 0) {
                        ptbase->type->base = obj->type;
                    }
                    ptbase = ptbase->next;
                }
                if (level == 0) {
                    ORG_BuildTD(tp, &dc);
                }
            }
            Check(ORS_semicolon, "; missing");
        }
    }
    
    if (sym == ORS_var) {
        ORS_Get(&sym);
        while (sym == ORS_ident) {
            IdentList(ORB_Var, &first);
            Type(&tp);
            obj = first;
            while (obj != NULL) {
                obj->type = tp;
                obj->lev = level;
                // 65C816: No alignment needed
                if (level > 0) {
                    // Local variable: assign preliminary offset (will be reordered below)
                    obj->val = 1 + parblksize + *varsize;
                } else {
                    // Global variable: use absolute address
                    obj->val = *varsize;
                }
                *varsize = *varsize + obj->type->size;
                if (obj->expo) {
                    obj->exno = exno;
                    exno++;
                }
                obj = obj->next;
            }
            Check(ORS_semicolon, "; missing");
        }
    }

    // 65C816: Reorder local variable offsets to keep scalars within
    // 8-bit stack-relative offset range. LDA nn,S only supports nn=0..255.
    // Place small types first (low offsets), large arrays/records last.
    // IMPORTANT: Only reorder LOCAL variables (val > parblksize), not parameters.
    // Parameters have val in [1, parblksize], locals have val >= 1 + parblksize.
    // Value params with class=ORB_Var look the same as locals but must keep
    // their FPSection-assigned offsets.
    if (level > 0 && *varsize > 0) {
        LONGINT reorder_ofs = 0;
        ORB_Object *p;
        // Pass 1: small types (size <= 8) get low offsets
        for (p = topScope->next; p != NULL; p = p->next) {
            if (p->class == ORB_Var && p->lev == level && p->val > parblksize && p->type->size <= 8) {
                p->val = 1 + parblksize + reorder_ofs;
                reorder_ofs += p->type->size;
            }
        }
        // Pass 2: large types get high offsets
        for (p = topScope->next; p != NULL; p = p->next) {
            if (p->class == ORB_Var && p->lev == level && p->val > parblksize && p->type->size > 8) {
                p->val = 1 + parblksize + reorder_ofs;
                reorder_ofs += p->type->size;
            }
        }
    }
    
    // 65C816: No final alignment needed
    ptbase = pbsList;
    while (ptbase != NULL) {
        if (ptbase->type->base->form == ORB_Int) {
            ORS_Mark("undefined pointer base of");
        }
        ptbase = ptbase->next;
    }
    if ((sym >= ORS_const) && (sym <= ORS_var)) {
        ORS_Mark("declaration in bad order");
    }
}

static void ProcedureDecl(void) {
    ORB_Object *proc;
    ORB_Type *type;
    ORS_Ident procid;
    ORG_Item x;
    LONGINT locblksize, parblksize, L;
    BOOLEAN int_proc;
    
    int_proc = FALSE;
    ORS_Get(&sym);
    if (sym == ORS_times) {
        ORS_Get(&sym);
        int_proc = TRUE;
    }
    if (sym == ORS_ident) {
        strcpy(procid, ORS_id);
        ORS_Get(&sym);
        NewObj(&proc, procid, ORB_Const);
        if (int_proc) {
            parblksize = 12;
        } else {
            parblksize = 0;  // 65C816: Start with 0, let ProcedureType calculate actual parameter space
        }
        type = (ORB_Type*)calloc(1, sizeof(ORB_Type));
        type->form = ORB_Proc;
        type->size = 4;
        proc->type = type;
        proc->val = -1;
        proc->lev = level;
        CheckExport(&proc->expo);
        if (proc->expo) {
            proc->exno = exno;
            exno++;
        }
        OpenScope();
        level++;
        type->base = noType;
        ProcedureType(type, &parblksize);
        Check(ORS_semicolon, "no ;");
        locblksize = 0;
        Declarations(&locblksize, parblksize);
        proc->val = ORG_Here();
        proc->type->dsc = topScope->next;
        if (sym == ORS_procedure) {
            L = 0;
            ORG_FJump(&L);
            do {
                ProcedureDecl();
                Check(ORS_semicolon, "no ;");
            } while (sym == ORS_procedure);
            ORG_FixOne(L);
            proc->val = ORG_Here();  // 65C816 uses byte addresses, no multiplication needed
            proc->type->dsc = topScope->next;
        }
        // Store frame size in procedure type for caller access
        type->size = locblksize;
        ORG_Enter(proc, topScope->next, parblksize, locblksize, int_proc);
        if (sym == ORS_begin) {
            ORS_Get(&sym);
            StatSequence();
        }
        if (sym == ORS_return) {
            ORS_Get(&sym);
            if (type->base->form != ORB_NoTyp) {
                // Function - must have expression
                expression(&x);
                if (!CompTypes(type->base, x.type, FALSE)) {
                    ORS_Mark("wrong result type");
                }
            } else {
                // Procedure - no expression allowed
                x.type = noType;
            }
        } else if (type->base->form != ORB_NoTyp) {
            ORS_Mark("function without result");
            type->base = noType;
        }
        ORG_Return(proc, &x);
        CloseScope();
        level--;
        Check(ORS_end, "no END");
        if (sym == ORS_ident) {
            if (strcmp(ORS_id, procid) != 0) {
                ORS_Mark("no match");
            }
            ORS_Get(&sym);
        } else {
            ORS_Mark("no proc id");
        }
    } else {
        ORS_Mark("proc id expected");
    }
}

static void ORP_Import(void) {
    ORS_Ident impid, impid1;
    
    if (sym == ORS_ident) {
        strcpy(impid, ORS_id);
        ORS_Get(&sym);
        if (sym == ORS_becomes) {
            ORS_Get(&sym);
            if (sym == ORS_ident) {
                strcpy(impid1, ORS_id);
                ORS_Get(&sym);
            } else {
                ORS_Mark("id expected");
                strcpy(impid1, impid);
            }
        } else {
            strcpy(impid1, impid);
        }
        Import(impid, impid1);
    } else {
        ORS_Mark("id expected");
    }
}

static void ORP_Module(void) {
    LONGINT key = 0;
    
    Texts_WriteString(&W, "  compiling ");
    ORS_Get(&sym);
    if (sym == ORS_module) {
        ORS_Get(&sym);
		dc = 0;
        // ORS_Init should be called before this function
        OpenScope();
        if (sym == ORS_ident) {
            strcpy(modid, ORS_id);
            ORS_Get(&sym);
            Texts_WriteString(&W, modid);
            Texts_Append(Oberon_Log, W.buf);
            Texts_ClearWriter(&W);
        } else {
            ORS_Mark("identifier expected");
        }
        Check(ORS_semicolon, "no ;");
        level = 0;
        exno = 1;
        if (sym == ORS_import) {
                ORS_Get(&sym);
            ORP_Import();
            while (sym == ORS_comma) {
                ORS_Get(&sym);
                ORP_Import();
            }
            Check(ORS_semicolon, "; missing");
        }
        ORG_Open(modid, VERSION);
        Declarations(&dc, 0);  // Module level - no parameters
        ORG_SetDataSize(dc);
        while (sym == ORS_procedure) {
            ProcedureDecl();
            Check(ORS_semicolon, "no ;");
        }
        ORG_Header();
        if (sym == ORS_begin) {
            ORS_Get(&sym);
            StatSequence();
        }
        Check(ORS_end, "no END");
        if (sym == ORS_ident) {
            if (strcmp(ORS_id, modid) != 0) {
                ORS_Mark("no match");
            }
            ORS_Get(&sym);
        } else {
            ORS_Mark("identifier missing");
        }
        if (sym != ORS_period) {
            ORS_Mark("period missing");
        } else {
            ORS_Get(&sym);  // Consume the period
            if (sym != ORS_eof) {
                ORS_Mark("garbage after module");
            }
        }
        if (ORS_errcnt == 0) {
            Export(modid, &newSF, &key);
            if (newSF) {
                Texts_WriteString(&W, " new symbol file");
            }
        }
        if (ORS_errcnt == 0) {
            ORG_Close(modid, key, exno);
            Texts_WriteInt(&W, ORG_pc, 6);
            Texts_WriteInt(&W, dc, 6);
            Texts_WriteHex(&W, key);
        } else {
            Texts_WriteLn(&W);
            Texts_WriteString(&W, "compilation FAILED");
        }
        Texts_WriteLn(&W);
        Texts_Append(Oberon_Log, W.buf);
        Texts_ClearWriter(&W);
        CloseScope();
        pbsList = NULL;
    } else {
        ORS_Mark("must start with MODULE");
    }
}


void ORP_Compile(const char *filename, bool forceNewSF) {
    Texts_Text *T;
    
    if (!filename) {
        Texts_WriteString(&W, "Error: No filename provided");
        Texts_WriteLn(&W);
        Texts_Append(Oberon_Log, W.buf);
        Texts_ClearWriter(&W);
        return;
    }
    
    // Set the source directory for output file placement
    SetSourceDirectory(filename);
    
    newSF = forceNewSF;
    
    Texts_WriteString(&W, "Compiling ");
    Texts_WriteString(&W, (char*)filename);
    Texts_WriteLn(&W);
    Texts_Append(Oberon_Log, W.buf);
    Texts_ClearWriter(&W);
    
    T = (Texts_Text*)malloc(sizeof(Texts_Text));
    if (!T) {
        Texts_WriteString(&W, "Error: Memory allocation failed");
        Texts_WriteLn(&W);
        Texts_Append(Oberon_Log, W.buf);
        Texts_ClearWriter(&W);
        return;
    }
    
    Texts_Open(T, (char*)filename);
    if (T->len > 0) {
        ORS_Init(T, 0);
        ORP_Module();
    } else {
        Texts_WriteString(&W, "Error: File not found or empty: ");
        Texts_WriteString(&W, (char*)filename);
        Texts_WriteLn(&W);
        Texts_Append(Oberon_Log, W.buf);
        Texts_ClearWriter(&W);
    }
    
    if (T) {
        Texts_Close(T);
        free(T);
    }
}

// Resolved at startup: directory containing the runtime modules (Out.Mod,
// Modules.Mod, runtime.c, etc.). Auto-compile and the linker look here as
// a fallback when a module isn't in the user's source directory.
static char RuntimeDir[1024] = "";

static void resolve_runtime_dir(const char *self_argv0) {
    char self_abs[1024];
    if (realpath(self_argv0, self_abs) == NULL) return;
    char *last_slash = strrchr(self_abs, '/');
    if (!last_slash) return;
    *last_slash = 0;
    static const char *layouts[] = { "/../oberon/", "/oberon/", NULL };
    for (int i = 0; layouts[i]; i++) {
        snprintf(RuntimeDir, sizeof(RuntimeDir), "%s%s", self_abs, layouts[i]);
        if (access(RuntimeDir, R_OK) == 0) return;
    }
    RuntimeDir[0] = 0;
}

// Find a runtime .c file relative to the running compiler binary.
// Used for runtime.c (always included), Modules_rt.c (included when the
// transitive import graph mentions the Modules module), etc.
static int find_runtime_file(const char *self_argv0, const char *basename,
                             char *out, size_t outsz) {
    char self_abs[1024];
    if (realpath(self_argv0, self_abs) == NULL) return -1;
    char *last_slash = strrchr(self_abs, '/');
    if (!last_slash) return -1;
    *last_slash = 0;
    static const char *layouts[] = {
        "/../oberon/", "/oberon/", "/", NULL,
    };
    for (int i = 0; layouts[i]; i++) {
        snprintf(out, outsz, "%s%s%s", self_abs, layouts[i], basename);
        if (access(out, R_OK) == 0) return 0;
    }
    return -1;
}

static int find_runtime_source(const char *self_argv0,
                               char *out, size_t outsz) {
    return find_runtime_file(self_argv0, "runtime.c", out, outsz);
}

// Auto-link helper: walks the transitive .deps closure rooted at entry,
// generates a tiny C main() that calls <entry>__init(), and shells out to
// clang to produce a native binary linking entry.ll, all transitive .ll
// files, and any user-supplied extras (.c / .o / -lfoo / etc).
#define MAX_LINK_MODS 64
#define MAX_LINK_NAME 64

static BOOLEAN list_has(char names[][MAX_LINK_NAME], int n, const char *s) {
    for (int i = 0; i < n; i++) if (strcmp(names[i], s) == 0) return TRUE;
    return FALSE;
}

// --- Recursive auto-compile: invoked by `oc -o prog Main.Mod` so the user
// only has to keep the `.Mod` files up to date; the driver compiles each
// transitive import that's missing or older than its source.

// Locate a module's .Mod source. Tries the user's source dir first, then
// the runtime dir (oberon/ next to the compiler binary). Returns 0 on
// success, -1 if neither path exists.
static int locate_module_source(const char *source_dir, const char *modname,
                                char *out, size_t outsz) {
    snprintf(out, outsz, "%s%s.Mod", source_dir, modname);
    if (access(out, R_OK) == 0) return 0;
    if (RuntimeDir[0]) {
        snprintf(out, outsz, "%s%s.Mod", RuntimeDir, modname);
        if (access(out, R_OK) == 0) return 0;
    }
    return -1;
}

// Same idea for a module's .o (used by the linker).
static int locate_module_object(const char *source_dir, const char *modname,
                                char *out, size_t outsz) {
    snprintf(out, outsz, "%s%s.o", source_dir, modname);
    if (access(out, R_OK) == 0) return 0;
    if (RuntimeDir[0]) {
        snprintf(out, outsz, "%s%s.o", RuntimeDir, modname);
        if (access(out, R_OK) == 0) return 0;
    }
    return -1;
}

// Quick textual scanner for `IMPORT a, b := c, d;` clauses. Strips nested
// (* *) comments first. Reads up to 16 KB of the source which is more
// than enough to reach the IMPORT clause at the top of the module.
static int scan_imports(const char *source_dir, const char *modname,
                        char out[][MAX_LINK_NAME], int max) {
    char path[512];
    if (locate_module_source(source_dir, modname, path, sizeof(path)) != 0) {
        return 0;
    }
    FILE *f = fopen(path, "r");
    if (!f) return 0;
    char buf[16384];
    size_t n = fread(buf, 1, sizeof(buf) - 1, f);
    buf[n] = 0;
    fclose(f);

    // Strip nested Oberon comments by overwriting them with spaces so
    // identifier scanning still has the right line/column anchoring.
    int depth = 0;
    for (size_t i = 0; i + 1 < n; ) {
        if (depth == 0 && buf[i] == '(' && buf[i+1] == '*') {
            buf[i] = ' '; buf[i+1] = ' '; depth = 1; i += 2;
        } else if (depth > 0 && buf[i] == '(' && buf[i+1] == '*') {
            buf[i] = ' '; buf[i+1] = ' '; depth++; i += 2;
        } else if (depth > 0 && buf[i] == '*' && buf[i+1] == ')') {
            buf[i] = ' '; buf[i+1] = ' '; depth--; i += 2;
        } else {
            if (depth > 0 && buf[i] != '\n') buf[i] = ' ';
            i++;
        }
    }

    char *imp = strstr(buf, "IMPORT");
    if (!imp) return 0;
    char *q = imp + 6;
    int count = 0;
    while (*q && *q != ';' && count < max) {
        while (*q && (isspace((unsigned char)*q) || *q == ',')) q++;
        if (!*q || *q == ';') break;
        char name[MAX_LINK_NAME];
        int i = 0;
        while (*q && (isalnum((unsigned char)*q) || *q == '_') && i < MAX_LINK_NAME - 1) {
            name[i++] = *q++;
        }
        name[i] = 0;
        // alias `M := Real` — keep the actual module name.
        while (*q && isspace((unsigned char)*q)) q++;
        if (q[0] == ':' && q[1] == '=') {
            q += 2;
            while (*q && isspace((unsigned char)*q)) q++;
            i = 0;
            while (*q && (isalnum((unsigned char)*q) || *q == '_') && i < MAX_LINK_NAME - 1) {
                name[i++] = *q++;
            }
            name[i] = 0;
        }
        if (i > 0 && strcmp(name, "SYSTEM") != 0) {
            strncpy(out[count], name, MAX_LINK_NAME - 1);
            out[count][MAX_LINK_NAME - 1] = 0;
            count++;
        }
    }
    return count;
}

// True iff the module's .Mod (in user dir or runtime dir) is newer than
// its .smb / .o sitting next to it, or those outputs are missing.
static int needs_compile(const char *source_dir, const char *modname) {
    char mod_path[512];
    if (locate_module_source(source_dir, modname, mod_path, sizeof(mod_path)) != 0) {
        return 0;   // can't find source — caller will get import errors
    }
    // Use the .Mod's containing directory for the output check.
    char dir[512];
    int last_sep = -1;
    for (int i = 0; mod_path[i]; i++) {
        if (mod_path[i] == '/' || mod_path[i] == '\\') last_sep = i;
    }
    if (last_sep < 0) { dir[0] = 0; }
    else {
        size_t n = (size_t)(last_sep + 1);
        if (n >= sizeof(dir)) n = sizeof(dir) - 1;
        memcpy(dir, mod_path, n);
        dir[n] = 0;
    }
    char smb_path[512], o_path[512];
    snprintf(smb_path, sizeof(smb_path), "%s%s.smb", dir, modname);
    snprintf(o_path,   sizeof(o_path),   "%s%s.o",   dir, modname);
    struct stat mod_st, smb_st, o_st;
    if (stat(mod_path, &mod_st) != 0) return 0;
    if (stat(smb_path, &smb_st) != 0) return 1;
    if (stat(o_path,   &o_st)   != 0) return 1;
    return mod_st.st_mtime > smb_st.st_mtime
        || mod_st.st_mtime > o_st.st_mtime;
}

static void derive_source_dir(const char *fname, char *out, size_t outsz) {
    int last = -1;
    for (int i = 0; fname[i]; i++) {
        if (fname[i] == '/' || fname[i] == '\\') last = i;
    }
    if (last >= 0) {
        size_t n = (size_t)(last + 1);
        if (n >= outsz) n = outsz - 1;
        memcpy(out, fname, n);
        out[n] = 0;
    } else {
        out[0] = 0;
    }
}

static int ensure_compiled(const char *self_argv0, const char *source_dir,
                           const char *name,
                           char visited[][MAX_LINK_NAME], int *nv) {
    for (int i = 0; i < *nv; i++) {
        if (strcmp(visited[i], name) == 0) return 0;
    }
    if (*nv >= MAX_LINK_MODS) {
        fprintf(stderr, "oc: import graph too deep\n");
        return 1;
    }
    strncpy(visited[*nv], name, MAX_LINK_NAME - 1);
    visited[*nv][MAX_LINK_NAME - 1] = 0;
    (*nv)++;

    char imps[MAX_LINK_MODS][MAX_LINK_NAME];
    int nimp = scan_imports(source_dir, name, imps, MAX_LINK_MODS);
    for (int i = 0; i < nimp; i++) {
        if (ensure_compiled(self_argv0, source_dir, imps[i], visited, nv) != 0) {
            return 1;
        }
    }

    if (needs_compile(source_dir, name)) {
        char src_path[512];
        if (locate_module_source(source_dir, name, src_path, sizeof(src_path)) != 0) {
            return 0;   // not found anywhere — let the import phase complain
        }
        char cmd[1024];
        snprintf(cmd, sizeof(cmd), "'%s' '%s'", self_argv0, src_path);
        int rc = system(cmd);
        if (rc != 0) {
            fprintf(stderr, "oc: failed to compile %s (rc=%d)\n", name, rc);
            return rc ? rc : 1;
        }
    }
    return 0;
}

static int oc_link(const char *self_argv0, const char *output,
                   const char *entry, BOOLEAN include_runtime,
                   BOOLEAN shared, int n_extras, char **extras) {
    char modules[MAX_LINK_MODS][MAX_LINK_NAME];
    int  nmod = 0;
    char queue[MAX_LINK_MODS][MAX_LINK_NAME];
    int  qhead = 0, qtail = 0;

    strncpy(queue[qtail++], entry, MAX_LINK_NAME - 1);

    while (qhead < qtail) {
        const char *m = queue[qhead++];
        if (list_has(modules, nmod, m)) continue;
        if (nmod >= MAX_LINK_MODS) {
            fprintf(stderr, "oc: too many modules in transitive closure\n");
            return 1;
        }
        strncpy(modules[nmod], m, MAX_LINK_NAME - 1);
        modules[nmod][MAX_LINK_NAME - 1] = 0;
        nmod++;

        char path[512];
        const char *sd = GetSourceDir();
        snprintf(path, sizeof(path), "%s%s.deps", sd ? sd : "", m);
        FILE *f = fopen(path, "r");
        if (!f) continue;       // module has no recorded imports
        char line[MAX_LINK_NAME];
        while (fgets(line, sizeof(line), f)) {
            line[strcspn(line, "\r\n")] = 0;
            if (!line[0]) continue;
            if (qtail < MAX_LINK_MODS &&
                !list_has(queue, qtail, line) &&
                !list_has(modules, nmod, line)) {
                strncpy(queue[qtail], line, MAX_LINK_NAME - 1);
                queue[qtail][MAX_LINK_NAME - 1] = 0;
                qtail++;
            }
        }
        fclose(f);
    }

    char main_path[512] = "";
    const char *sd = GetSourceDir();
    if (!shared) {
        // Synthesize main.c next to the source dir for executables.
        snprintf(main_path, sizeof(main_path), "%s.oc_main_%d.c",
                 sd ? sd : "", (int)getpid());
        FILE *mf = fopen(main_path, "w");
        if (!mf) {
            fprintf(stderr, "oc: cannot write %s\n", main_path);
            return 1;
        }
        fprintf(mf,
            "extern void %s__init(void);\n"
            "int main(int argc, char **argv) {\n"
            "    (void)argc; (void)argv;\n"
            "    %s__init();\n"
            "    return 0;\n"
            "}\n", entry, entry);
        fclose(mf);
    }

    // Build the clang command line. Single-quoted args handle spaces.
    char cmd[8192];
    // -shared: produce a dylib whose unresolved symbols are looked up by
    // dyld at load time against the host process. The runtime / imports
    // need to be statically linked into the host (or loaded ahead of us).
    int p;
    if (shared) {
        p = snprintf(cmd, sizeof(cmd),
            "clang -shared -Wl,-undefined,dynamic_lookup -o '%s'", output);
    } else {
        p = snprintf(cmd, sizeof(cmd),
            "clang -o '%s' '%s'", output, main_path);
    }
    if (shared) {
        // Shared mode: only the entry module's .o goes in the dylib.
        // Imports stay as undefined symbols resolved at load time —
        // either by another loaded dylib or by the host process.
        char obj[512];
        if (locate_module_object(sd ? sd : "", entry, obj, sizeof(obj)) == 0) {
            p += snprintf(cmd + p, sizeof(cmd) - p, " '%s'", obj);
        }
    } else {
        for (int i = 0; i < nmod; i++) {
            char obj[512];
            if (locate_module_object(sd ? sd : "", modules[i], obj, sizeof(obj)) == 0) {
                p += snprintf(cmd + p, sizeof(cmd) - p, " '%s'", obj);
            } else {
                fprintf(stderr,
                    "oc: warning: %s.o missing — module not linked (compile %s.Mod first?)\n",
                    modules[i], modules[i]);
            }
        }
    }
    if (include_runtime && !shared) {
        // Runtime is statically linked into the host. Shared modules
        // resolve oc_alloc / oc_retain / oc_release against the host at
        // load time via -undefined dynamic_lookup.
        char rt_path[1024];
        if (find_runtime_source(self_argv0, rt_path, sizeof(rt_path)) == 0) {
            p += snprintf(cmd + p, sizeof(cmd) - p, " '%s'", rt_path);
        } else {
            fprintf(stderr,
                "oc: warning: runtime.c not found near %s — "
                "ARC symbols (oc_alloc / oc_retain / oc_release) will be "
                "unresolved. Pass --no-runtime to silence this and supply "
                "your own implementation.\n", self_argv0);
        }
        // For every module in the transitive import closure, look for an
        // <Mod>_rt.c sidecar next to the runtime modules and link it in.
        // This is how Modules / Files / Kernel / etc. get their strong
        // overrides into the host without the user having to remember.
        for (int i = 0; i < nmod; i++) {
            char rt_name[256], rt_path[1024];
            snprintf(rt_name, sizeof(rt_name), "%s_rt.c", modules[i]);
            if (find_runtime_file(self_argv0, rt_name, rt_path, sizeof(rt_path)) == 0) {
                p += snprintf(cmd + p, sizeof(cmd) - p, " '%s'", rt_path);
            }
        }
    }
    for (int i = 0; i < n_extras; i++) {
        p += snprintf(cmd + p, sizeof(cmd) - p, " '%s'", extras[i]);
    }

    int rc = system(cmd);
    if (main_path[0]) unlink(main_path);
    if (rc != 0) {
        fprintf(stderr, "oc: link failed (clang exit %d)\n", rc);
        return rc ? rc : 1;
    }
    printf("Linked %s\n", output);
    return 0;
}

static void modid_from_filename(const char *fname, char *out, size_t outsz) {
    const char *base = strrchr(fname, '/');
    base = base ? base + 1 : fname;
    const char *bs = strrchr(base, '\\');
    if (bs) base = bs + 1;
    size_t i = 0;
    while (base[i] && base[i] != '.' && i + 1 < outsz) {
        out[i] = base[i];
        i++;
    }
    out[i] = 0;
}

int main(int argc, char **argv) {
    const char *filename = NULL;
    const char *output = NULL;
    char *extras[64];
    int n_extras = 0;
    bool forceNewSF = false;
    bool emit_obj = true;       // override with -S
    bool do_link = false;       // set by -o
    bool include_runtime = true;// override with --no-runtime
    bool shared = false;        // -shared: build a dylib instead of an exe
    int i;

    if (argc < 2) {
        printf("Usage: %s [flags] <module.Mod> [extras...]\n", argv[0]);
        printf("  -s              Force new symbol file\n");
        printf("  -I<dir>         Add symbol file search path\n");
        printf("  -c              Compile only (default; no link)\n");
        printf("  -S              Emit only .ll, skip .o\n");
        printf("  -o <prog>       Auto-link transitive imports into native binary\n");
        printf("  -shared         Produce a .dylib (load via Modules.Load at runtime)\n");
        printf("  --no-runtime    Don't auto-include oberon/runtime.c in the link\n");
        printf("  extras          Passed through to clang (e.g. Out_rt.c, -lm)\n");
        return 1;
    }

    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-s") == 0 || strcmp(argv[i], "/s") == 0) {
            forceNewSF = true;
        } else if (strcmp(argv[i], "-c") == 0) {
            do_link = false;        // explicit no-link (also the default)
        } else if (strcmp(argv[i], "-S") == 0) {
            emit_obj = false;
            do_link = false;        // can't link without object code
        } else if (strcmp(argv[i], "--no-runtime") == 0) {
            include_runtime = false;
        } else if (strcmp(argv[i], "-shared") == 0) {
            shared = true;
        } else if (strcmp(argv[i], "-o") == 0) {
            if (i + 1 < argc) { output = argv[++i]; do_link = true; }
            else { fprintf(stderr, "oc: -o expects an argument\n"); return 1; }
        } else if (strncmp(argv[i], "-I", 2) == 0) {
            if (argv[i][2] != '\0') {
                AddSearchPath(&argv[i][2]);
            } else if (i + 1 < argc) {
                AddSearchPath(argv[++i]);
            }
        } else if (filename == NULL && strstr(argv[i], ".Mod")) {
            filename = argv[i];
        } else {
            if (n_extras < 64) extras[n_extras++] = argv[i];
        }
    }

    // -S without -o is fine (just inspect IR). -S with -o is contradictory
    // — we need .o files to link. Ignore the link request in that case.
    if (!emit_obj && do_link) {
        fprintf(stderr, "oc: -S and -o are incompatible (need .o to link)\n");
        return 1;
    }

    // Locate the runtime modules directory (oberon/ next to bin/oc) and
    // add it as a symbol-file search path so importers can find Out.smb,
    // Modules.smb, etc., without explicit -I flags.
    resolve_runtime_dir(argv[0]);
    if (RuntimeDir[0]) AddSearchPath(RuntimeDir);

    if (filename == NULL) {
        printf("Usage: %s [-s] [-I<dir>] [-o <prog>] <module.Mod> [extras...]\n", argv[0]);
        return 1;
    }

    // When -o is set, recursively compile any stale imports BEFORE we
    // initialise the front-end for the main module — the imports need
    // their .smb files in place by the time we parse the IMPORT clause.
    if (do_link) {
        char source_dir_buf[512];
        char entry_modid[64];
        derive_source_dir(filename, source_dir_buf, sizeof(source_dir_buf));
        modid_from_filename(filename, entry_modid, sizeof(entry_modid));
        char visited[MAX_LINK_MODS][MAX_LINK_NAME];
        int nv = 0;
        char main_imps[MAX_LINK_MODS][MAX_LINK_NAME];
        int nimp = scan_imports(source_dir_buf, entry_modid, main_imps, MAX_LINK_MODS);
        for (int j = 0; j < nimp; j++) {
            if (ensure_compiled(argv[0], source_dir_buf,
                                main_imps[j], visited, &nv) != 0) {
                return 1;
            }
        }
    }

    Texts_OpenWriter(&W);
    Texts_WriteString(&W, "Oberon LLVM Compiler  Version ");
    Texts_WriteInt(&W, VERSION, 1);
    Texts_WriteLn(&W);
    Texts_Append(Oberon_Log, W.buf);
    Texts_ClearWriter(&W);

    ORB_Initialize();
    ORB_Init();

    dummy = (ORB_Object*)calloc(1, sizeof(ORB_Object));
    dummy->class = ORB_Var;
    dummy->type = intType;

    expression = expression0;
    Type = Type0;
    FormalType = FormalType0;

    ORG_Init();
    ORG_SetEmitFlags(TRUE, emit_obj);
    ORP_Compile(filename, forceNewSF);

    if (ORS_errcnt > 0) {
        printf("Compilation failed with %d errors\n", ORS_errcnt);
        return 1;
    }
    printf("Compilation successful\n");

    if (do_link) {
        char modid_buf[64];
        modid_from_filename(filename, modid_buf, sizeof(modid_buf));
        return oc_link(argv[0], output, modid_buf,
                       include_runtime, shared, n_extras, extras);
    }
    return 0;
}
