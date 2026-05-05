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

// disasm.c - 65C816 Disassembler for .816 files
// Disassembles compiled Oberon modules to help with debugging

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include "cpu.h"
#include "Files.h"
#include "Oberon.h"

// Code base address - must match ORG.c
#define CODE_ORG 0x0000

// Global relocation tracking
static int relocation_count = 0;
static int relocation_addresses[1024]; // Max relocations
static int current_relocation_index = 0; // Current position in relocation array

// Structure to represent a disassembled instruction
typedef struct {
    uint32_t address;
    uint8_t opcode;
    uint8_t operand1;
    uint8_t operand2;
    uint8_t operand3;
    int length;
    OpCode instruction;
    AddrMode mode;
    int value;
} DisasmInstr;

// 65C816 processor status tracking
typedef struct {
    bool m_flag;  // Memory/Accumulator size (0=16-bit, 1=8-bit)
    bool x_flag;  // Index register size (0=16-bit, 1=8-bit)
    bool emulation_mode;
} ProcessorStatus;

static ProcessorStatus cpu_status = {false, false, false}; // Start in native mode with 16-bit A/X/Y (longa/longi on)

// Update processor status based on instruction
static void update_processor_status(uint8_t opcode, int operand) {
    switch (opcode) {
        case 0xFB: // XCE - Exchange Carry and Emulation
            // This toggles emulation mode based on carry, but we'll assume native mode
            cpu_status.emulation_mode = false;
            // When switching to native mode, processor flags retain their values
            // but M and X flags become meaningful for register sizes
            break;
            
        case 0xE2: // SEP - Set Processor Status
            if (operand & 0x20) cpu_status.m_flag = true;  // Set M flag (8-bit A)
            if (operand & 0x10) cpu_status.x_flag = true;  // Set X flag (8-bit X/Y)
            break;
            
        case 0xC2: // REP - Reset Processor Status
            if (operand & 0x20) cpu_status.m_flag = false; // Clear M flag (16-bit A)
            if (operand & 0x10) cpu_status.x_flag = false; // Clear X flag (16-bit X/Y)
            break;
    }
}

// Determine addressing mode and operand length from opcode
static void decode_instruction(uint8_t opcode, AddrMode *mode, int *length) {
    switch (opcode) {
        // Implied mode (1 byte)
        case 0x18: // CLC
        case 0x38: // SEC
        case 0xFB: // XCE
        case 0xEA: // NOP
        case 0x40: // RTI
        case 0x60: // RTS
        case 0x6B: // RTL
            *mode = Implied;
            *length = 1;
            break;
            
        // Accumulator mode (1 byte) - shift/rotate operations
        case 0x0A: // ASL A
        case 0x4A: // LSR A
        case 0x2A: // ROL A
            *mode = Accumulator;
            *length = 1;
            break;
            
        // Direct Page Indexed Indirect X (2 bytes)
        case 0x21: // AND (dp,X)
        case 0x41: // EOR (dp,X)
        case 0x01: // ORA (dp,X)
            *mode = DirectPageIndexedIndirectX;
            *length = 2;
            break;
            
        // BRK instruction (2 bytes: opcode + signature)
        case 0x00: // BRK
            *mode = Immediate;
            *length = 2;
            break;
            
        // Immediate mode - length depends on M flag for A instructions
        case 0xA9: // LDA #
        case 0x69: // ADC #
        case 0xE9: // SBC #
        case 0xC9: // CMP #
        case 0x29: // AND #
        case 0x49: // EOR #
        case 0x09: // ORA #
            *mode = Immediate;
            *length = cpu_status.m_flag ? 2 : 3; // 8-bit or 16-bit A
            break;
            
        // Immediate mode - length depends on X flag for X/Y instructions
        case 0xA2: // LDX #
        case 0xA0: // LDY #
        case 0xE0: // CPX #
        case 0xC0: // CPY #
            *mode = Immediate;
            *length = cpu_status.x_flag ? 2 : 3; // 8-bit or 16-bit X/Y
            break;
            
        case 0xC2: // REP #
        case 0xE2: // SEP #
            *mode = Immediate;
            *length = 2; // Always 8-bit operand
            break;
            
        // Branch instructions (2 bytes)
        case 0x10: // BPL
        case 0x30: // BMI
        case 0x50: // BVC
        case 0x70: // BVS
        case 0x90: // BCC
        case 0xB0: // BCS
        case 0xD0: // BNE
        case 0xF0: // BEQ
        case 0x80: // BRA
            *mode = ProgramCounterRelative;
            *length = 2;
            break;
            
        // Branch long (3 bytes)
        case 0x82: // BRL
            *mode = ProgramCounterRelativeLong;
            *length = 3;
            break;
            
        // Direct Page (2 bytes)
        case 0xA5: // LDA dp
        case 0x85: // STA dp
        case 0xA6: // LDX dp
        case 0xA4: // LDY dp
        case 0x65: // ADC dp
        case 0xE5: // SBC dp
        case 0x25: // AND dp
        case 0x45: // EOR dp
        case 0x05: // ORA dp
        case 0x06: // ASL dp
        case 0x46: // LSR dp
        case 0x26: // ROL dp
            *mode = DirectPage;
            *length = 2;
            break;
            
        // Direct Page,X (2 bytes)
        case 0xB5: // LDA dp,X
        case 0x95: // STA dp,X
        case 0x75: // ADC dp,X
        case 0xF5: // SBC dp,X
        case 0x35: // AND dp,X
        case 0x55: // EOR dp,X
        case 0x15: // ORA dp,X
        case 0x16: // ASL dp,X
        case 0x56: // LSR dp,X
        case 0x36: // ROL dp,X
            *mode = DirectPageIndexedX;
            *length = 2;
            break;
            
        // Absolute (3 bytes)
        case 0xAD: // LDA abs
        case 0x8D: // STA abs
        case 0x6D: // ADC abs
        case 0xED: // SBC abs
        case 0x20: // JSR abs
        case 0x2D: // AND abs
        case 0x4D: // EOR abs
        case 0x0D: // ORA abs
        case 0x0E: // ASL abs
        case 0x4E: // LSR abs
        case 0x2E: // ROL abs
            *mode = Absolute;
            *length = 3;
            break;
            
        // Absolute Long (4 bytes)
        case 0x22: // JSL abs
            *mode = AbsoluteLong;
            *length = 4;
            break;
            
        // Absolute,X (3 bytes)
        case 0xBD: // LDA abs,X
        case 0x9D: // STA abs,X
        case 0x7D: // ADC abs,X
        case 0xFD: // SBC abs,X
        case 0x3D: // AND abs,X
        case 0x5D: // EOR abs,X
        case 0x1D: // ORA abs,X
        case 0x1E: // ASL abs,X
        case 0x5E: // LSR abs,X
        case 0x3E: // ROL abs,X
            *mode = AbsoluteIndexedX;
            *length = 3;
            break;
            
        // Absolute,Y (3 bytes)
        case 0xB9: // LDA abs,Y
        case 0x99: // STA abs,Y
        case 0x79: // ADC abs,Y
        case 0xF9: // SBC abs,Y
        case 0x39: // AND abs,Y
        case 0x59: // EOR abs,Y
        case 0x19: // ORA abs,Y
            *mode = AbsoluteIndexedY;
            *length = 3;
            break;
            
        // Direct Page Indirect (2 bytes)
        case 0xB2: // LDA (dp)
        case 0x92: // STA (dp)
        case 0x72: // ADC (dp)
        case 0xF2: // SBC (dp)
        case 0x32: // AND (dp)
        case 0x52: // EOR (dp)
        case 0x12: // ORA (dp)
            *mode = DirectPageIndirect;
            *length = 2;
            break;
            
        // Direct Page Indirect Long (2 bytes)
        case 0x07: // ORA [dp]
        case 0xA7: // LDA [dp]
        case 0x87: // STA [dp]
        case 0x27: // AND [dp]
        case 0x47: // EOR [dp]
            *mode = DirectPageIndirectLong;
            *length = 2;
            break;
            
        // Direct Page Indirect Long Indexed Y (2 bytes)
        case 0xB7: // LDA [dp],Y
        case 0x97: // STA [dp],Y
        case 0x37: // AND [dp],Y
        case 0x57: // EOR [dp],Y
        case 0x17: // ORA [dp],Y
            *mode = DirectPageIndirectLongIndexedY;
            *length = 2;
            break;
            
        // Direct Page Indirect Indexed Y (2 bytes)
        case 0xB1: // LDA (dp),Y
        case 0x91: // STA (dp),Y
        case 0x31: // AND (dp),Y
        case 0x51: // EOR (dp),Y
        case 0x11: // ORA (dp),Y
            *mode = DirectPageIndirectIndexedY;
            *length = 2;
            break;
            
        // Stack Relative (2 bytes)
        case 0xA3: // LDA sr,S
        case 0x83: // STA sr,S
        case 0xC3: // CMP sr,S
            *mode = StackRelative;
            *length = 2;
            break;
            
        // Stack Relative Indirect Indexed Y (2 bytes)
        case 0xB3: // LDA (sr,S),Y
        case 0x93: // STA (sr,S),Y
            *mode = StackRelativeIndirectIndexedY;
            *length = 2;
            break;
            
        default:
            *mode = Implied;
            *length = 1;
            break;
    }
}

// Format operand value based on addressing mode
static char* format_operand(AddrMode mode, int value) {
    static char buffer[32];
    
    switch (mode) {
        case Implied:
            buffer[0] = '\0';
            break;
        case Accumulator:
            strcpy(buffer, "A");
            break;
        case Immediate:
            // Format based on instruction width (8-bit or 16-bit)
            if (value <= 0xFF) {
                sprintf(buffer, "#$%02X", value & 0xFF);
            } else {
                sprintf(buffer, "#$%04X", value & 0xFFFF);
            }
            break;
        case DirectPage:
            sprintf(buffer, "$%02X", value & 0xFF);
            break;
        case DirectPageIndexedX:
            sprintf(buffer, "$%02X,X", value & 0xFF);
            break;
        case DirectPageIndirect:
            sprintf(buffer, "($%02X)", value & 0xFF);
            break;
        case DirectPageIndirectLong:
            sprintf(buffer, "[$%02X]", value & 0xFF);
            break;
        case DirectPageIndirectLongIndexedY:
            sprintf(buffer, "[$%02X],Y", value & 0xFF);
            break;
        case DirectPageIndirectIndexedY:
            sprintf(buffer, "($%02X),Y", value & 0xFF);
            break;
        case Absolute:
            sprintf(buffer, "$%04X", value);
            break;
        case AbsoluteLong:
            sprintf(buffer, "$%06X", value);
            break;
        case AbsoluteIndexedX:
            sprintf(buffer, "$%04X,X", value);
            break;
        case AbsoluteIndexedY:
            sprintf(buffer, "$%04X,Y", value);
            break;
        case StackRelative:
            sprintf(buffer, "$%02X,S", value & 0xFF);
            break;
        case StackRelativeIndirectIndexedY:
            sprintf(buffer, "($%02X,S),Y", value & 0xFF);
            break;
        case ProgramCounterRelative:
            // For branch instructions, show relative offset
            sprintf(buffer, "$%02X", value & 0xFF);
            break;
        case ProgramCounterRelativeLong:
            sprintf(buffer, "$%04X", value & 0xFFFF);
            break;
        default:
            sprintf(buffer, "???");
            break;
    }
    
    return buffer;
}

// Disassemble a single instruction from the code array
static int disassemble_instruction(uint8_t *code, int pc, DisasmInstr *instr) {
    instr->address = CODE_ORG + pc;  // Add code base to show actual memory address
    instr->opcode = code[pc];
    instr->instruction = byte_to_opcode(instr->opcode);
    
    decode_instruction(instr->opcode, &instr->mode, &instr->length);
    
    // Read operands based on instruction length
    instr->operand1 = (instr->length > 1) ? code[pc + 1] : 0;
    instr->operand2 = (instr->length > 2) ? code[pc + 2] : 0;
    instr->operand3 = (instr->length > 3) ? code[pc + 3] : 0;
    
    // Combine operands into value
    switch (instr->length) {
        case 1:
            instr->value = 0;
            break;
        case 2:
            instr->value = instr->operand1;
            break;
        case 3:
            instr->value = instr->operand1 | (instr->operand2 << 8);
            break;
        case 4:
            instr->value = instr->operand1 | (instr->operand2 << 8) | (instr->operand3 << 16);
            break;
    }
    
    // Update processor status for REP/SEP instructions
    if (instr->opcode == 0xC2 || instr->opcode == 0xE2 || instr->opcode == 0xFB) {
        update_processor_status(instr->opcode, instr->value);
    }
    
    return instr->length;
}

// Print a disassembled instruction
static void print_instruction(DisasmInstr *instr) {
    const char *mnemonic = opcode_to_string(instr->instruction);
    char *operand = format_operand(instr->mode, instr->value);
    
    // Print address and raw bytes
    printf("%04X: ", instr->address);
    
    // Print raw bytes (up to 4 bytes, padded)
    for (int i = 0; i < 4; i++) {
        if (i < instr->length) {
            switch (i) {
                case 0: printf("%02X ", instr->opcode); break;
                case 1: printf("%02X ", instr->operand1); break;
                case 2: printf("%02X ", instr->operand2); break;
                case 3: printf("%02X ", instr->operand3); break;
            }
        } else {
            printf("   ");
        }
    }
    
    // Print mnemonic and operand
    printf("%-4s %s", mnemonic, operand);
    
    // Add comments for special cases
    if (instr->mode == ProgramCounterRelative) {
        // Calculate branch target for relative branches
        int target = instr->address + instr->length + (int8_t)instr->operand1;
        printf("  ; -> $%04X", target);
    } else if (instr->mode == ProgramCounterRelativeLong) {
        // Calculate branch target for long relative branches  
        int16_t offset = instr->operand1 | (instr->operand2 << 8);
        int target = instr->address + instr->length + offset;
        printf("  ; -> $%04X", target);
    } else if (instr->instruction == sREP && instr->value == 0x30) {
        printf("  ; 16-bit A/X/Y");
    } else if (instr->instruction == sSEP && instr->value == 0x30) {
        printf("  ; 8-bit A/X/Y");
    } else if (instr->instruction == sXCE) {
        printf("  ; Native mode");
    } else if (instr->mode == Absolute && instr->value >= 0x1000 && instr->value < 0x2000) {
        printf("  ; Module variable");
    } else if (instr->mode == DirectPage) {
        printf("  ; Register $%02X", instr->value);
    }
    
    // Check for relocations at this address
    if (current_relocation_index < relocation_count && 
        relocation_addresses[current_relocation_index] <= (int)instr->address) {
        printf("  ; Relocation %d", current_relocation_index);
        current_relocation_index++;
    }
    
    printf("\n");
}

// Parse .816 file structure and extract code section
static int parse_816_file(const char *filename, uint8_t **code_data, int *code_size) {
    FILE *file = fopen(filename, "rb");
    if (!file) {
        printf("Error: Cannot open file %s\n", filename);
        return 0;
    }
    
    // Read module name (null-terminated string)
    char module_name[64];
    int name_len = 0;
    while (name_len < 63) {
        if (fread(&module_name[name_len], 1, 1, file) != 1) {
            printf("Error: Unexpected end of file reading module name\n");
            fclose(file);
            return 0;
        }
        if (module_name[name_len] == 0) break;
        name_len++;
    }
    module_name[name_len] = 0;
    
    printf("Module: %s\n", module_name);
    
    // Read key (4 bytes)
    uint32_t key;
    if (fread(&key, 4, 1, file) != 1) {
        printf("Error: Cannot read key\n");
        fclose(file);
        return 0;
    }
    
    // Read version (1 byte)
    uint8_t version;
    if (fread(&version, 1, 1, file) != 1) {
        printf("Error: Cannot read version\n");
        fclose(file);
        return 0;
    }
    
    // Read size (4 bytes)
    uint32_t size;
    if (fread(&size, 4, 1, file) != 1) {
        printf("Error: Cannot read size\n");
        fclose(file);
        return 0;
    }
    
    printf("Key: %08X, Version: %d, Size: %d bytes\n", key, version, size);
    
    // Read entry point from end of file
    long current_pos = ftell(file);
    fseek(file, -5, SEEK_END);  // Entry point is 4 bytes before the final 'O'
    uint32_t entry_point;
    if (fread(&entry_point, 4, 1, file) == 1) {
        printf("Entry point: $%04X (%d)\n", entry_point, entry_point);
    }
    fseek(file, current_pos, SEEK_SET);  // Restore position
    
    // Parse the file format step by step:
    // 1. Module name, key, version, size already read
    // 2. Skip import section
    while (1) {
        char ch;
        if (fread(&ch, 1, 1, file) != 1) break;
        if (ch == 0) break; // End of imports
        // Skip module name
        while (ch != 0) {
            if (fread(&ch, 1, 1, file) != 1) break;
        }
        // Skip module key (4 bytes)
        fseek(file, 4, SEEK_CUR);
    }
    
    // 3. Skip type descriptors
    uint32_t td_size;
    if (fread(&td_size, 4, 1, file) != 1) {
        printf("Error: Cannot read type descriptor size\n");
        fclose(file);
        return 0;
    }
    fseek(file, td_size, SEEK_CUR);
    
    // 4. Skip variable section
    uint32_t var_size;
    if (fread(&var_size, 4, 1, file) != 1) {
        printf("Error: Cannot read variable size\n");
        fclose(file);
        return 0;
    }
    
    // 5. Read and display string section
    uint32_t str_size;
    if (fread(&str_size, 4, 1, file) != 1) {
        printf("Error: Cannot read string size\n");
        fclose(file);
        return 0;
    }
    
    printf("String section: %d bytes\n", str_size);
    if (str_size > 0) {
        char *str_data = (char*)malloc(str_size);
        if (str_data && fread(str_data, 1, str_size, file) == str_size) {
            printf("String storage:\n");
            for (uint32_t i = 0; i < str_size; i += 16) {
                printf("  $%04X: ", 0x1000 + var_size + i); // Strings stored after variables at MODULE_VAR_BASE + varsize
                
                // Print hex bytes (16 per line with space after 8th byte)
                for (int j = 0; j < 16; j++) {
                    if ((i + j) < str_size) {
                        printf("%02X ", (unsigned char)str_data[i + j]);
                    } else {
                        printf("   ");
                    }
                    if (j == 7) printf(" "); // Extra space after 8th byte
                }
                
                // Print ASCII representation
                printf(" \"");
                for (int j = 0; j < 16 && (i + j) < str_size; j++) {
                    char c = str_data[i + j];
                    if (c >= 32 && c < 127) {
                        printf("%c", c);
                    } else if (c == 0) {
                        printf("\\0");
                    } else {
                        printf("\\x%02X", (unsigned char)c);
                    }
                }
                printf("\"\n");
            }
            free(str_data);
        } else {
            printf("Error: Cannot read string data\n");
            fseek(file, str_size, SEEK_CUR);
        }
    }
    printf("\n");
    
    // 6. Read code section length
    uint32_t code_length;
    if (fread(&code_length, 4, 1, file) != 1) {
        printf("Error: Cannot read code length\n");
        fclose(file);
        return 0;
    }
    *code_size = code_length;
    *code_data = (uint8_t*)malloc(*code_size);
    if (!*code_data) {
        printf("Error: Cannot allocate memory for code\n");
        fclose(file);
        return 0;
    }
    
    printf("Code length: %d bytes\n", *code_size);
    
    if ((int)(fread(*code_data, 1, *code_size, file)) != *code_size) {
        printf("Error: Cannot read code section\n");
        free(*code_data);
        fclose(file);
        return 0;
    }
    
    // Parse the rest of the file sequentially after the code section
    // Format: export_procs + export_values + pointer_table + fixups + relocations + entry + 'O'
    
    // Skip export procedures section (null-terminated strings with values)
    while (1) {
        char ch;
        if (fread(&ch, 1, 1, file) != 1) break;
        if (ch == 0) break; // End of export procedures
        // Skip procedure name
        while (ch != 0) {
            if (fread(&ch, 1, 1, file) != 1) break;
        }
        // Skip procedure value (4 bytes)
        fseek(file, 4, SEEK_CUR);
    }
    
    // Skip nofent and entry values (2 * 4 bytes)
    fseek(file, 8, SEEK_CUR);
    
    // Skip export values section - need to find how many exports there are
    // This is complex, so let's scan for the fixup marker (-1)
    uint32_t word;
    while (fread(&word, 4, 1, file) == 1) {
        if (word == 0xFFFFFFFF) { // Found -1 fixup marker
            break;
        }
    }
    
    // Read fixup information (fixorgP, fixorgD, fixorgT)
    int32_t fixorgP, fixorgD, fixorgT;
    if (fread(&fixorgP, 4, 1, file) != 1 ||
        fread(&fixorgD, 4, 1, file) != 1 ||
        fread(&fixorgT, 4, 1, file) != 1) {
        printf("Error reading fixup information\n");
        fclose(file);
        return 0;
    }
    
    // Read relocation table
    int32_t reloc_count;
    if (fread(&reloc_count, 4, 1, file) == 1) {
        if (reloc_count >= 0 && reloc_count < 1024) {
            printf("Relocation table: %d entries\n", reloc_count);
            
            // Store relocations in global array
            relocation_count = reloc_count;
            for (int i = 0; i < reloc_count; i++) {
                int32_t reloc_addr;
                if (fread(&reloc_addr, 4, 1, file) == 1) {
                    relocation_addresses[i] = reloc_addr;
                    printf("  $%04X\n", reloc_addr);
                }
            }
            if (reloc_count > 0) printf("\n");
        }
    }
    
    fclose(file);
    printf("Code section: %d bytes\n\n", *code_size);
    return 1;
}

// Main disassembler function
static void disassemble_code(uint8_t *code, int code_size) {
    int pc = 0;
    DisasmInstr instr;
    
    // Reset relocation index for new disassembly
    current_relocation_index = 0;
    
    printf("Disassembly:\n");
    printf("Addr: Bytes        Instruction\n");
    printf("-----------------------------\n");
    
    while (pc < code_size) {
        int advance = disassemble_instruction(code, pc, &instr);
        print_instruction(&instr);
        pc += advance;
        
        // Safety check to prevent infinite loops
        if (advance == 0) {
            printf("Error: Zero-length instruction at PC %04X\n", pc);
            break;
        }
    }
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s <file.816>\n", argv[0]);
        printf("Disassembles 65C816 compiled Oberon modules\n");
        return 1;
    }
    
    const char *filename = argv[1];
    uint8_t *code_data;
    int code_size;
    
    printf("65C816 Oberon Module Disassembler\n");
    printf("==================================\n\n");
    
    if (!parse_816_file(filename, &code_data, &code_size)) {
        return 1;
    }
    
    disassemble_code(code_data, code_size);
    
    free(code_data);
    return 0;
}
