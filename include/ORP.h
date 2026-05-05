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

/* ORP.h - Parser Header */
/* Original: N. Wirth 1.7.97 / 8.3.2020 Oberon compiler for RISC in Oberon-07 */
/* Parser of Oberon-RISC compiler. Uses Scanner ORS to obtain symbols (tokens),
   ORB for definition of data structures and for handling import and export, and
   ORG to produce binary code. ORP performs type checking and data allocation.
   Parser is target-independent, except for part of the handling of allocations. */

#ifndef ORP_H
#define ORP_H

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include "ORS.h"
#include "ORB.h"

/* Oberon 65C816 Compiler Version 1 */
#define VERSION 1

/* ORG Item structure - placeholder for code generator interface */
typedef struct {
    int mode;
    TypePtr type;
    int32_t a, b, c, r;
    bool rdo;
} Item;

/* Pointer base type list */
typedef struct PtrBase* PtrBasePtr;
typedef struct PtrBase {
    ORS_Ident name;
    TypePtr type;
    PtrBasePtr next;
} PtrBase;

/* Global variables */
//extern INTEGER sym;              /* last symbol read */
//extern int32_t dc;          /* data counter */
//extern int level, exno, version;
//extern bool newSF;          /* option flag */
//extern Ident modid;
//extern PtrBasePtr pbsList;  /* list of names of pointer base types */
//extern ObjectPtr dummy;

/* Main parsing functions */
void Module(void);
void ORP_Compile(const char *filename, bool forceNewSF);

/* Parser initialization */
int main(int argc, char **argv);

#endif /* ORP_H */
