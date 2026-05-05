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

// ORTool.h - Oberon Tool for decoding symbol and object files

#ifndef ORTOOL_H
#define ORTOOL_H

#include "Oberon.h"
#include "Texts.h"
#include "Files.h"
#include "ORB.h"

// Main functions
void ORTool_DecSym(void);    // Decode symbol file
void ORTool_DecObj(void);    // Decode object file
void ORTool_Init(void);      // Initialize module

#endif // ORTOOL_H
