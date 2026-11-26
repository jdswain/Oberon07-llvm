# 65C816 Oberon Runtime Environment

This document describes the runtime environment for the Oberon compiler
targeting the WDC 65C816 processor. It covers the memory map, register
usage, calling convention, code generation patterns, and object file format.

## 1. Memory Map

```
Bank 0 (System)
  $0000-$001F   Direct Page: Virtual register file (R0-R7, SB)
  $0020-$00FF   Direct Page: Available for future use
  $0100-$01FF   Hardware stack (S register)
  $0200-$0FFF   Reserved
  $1000-$xxxx   Module global variables (SB points here)
  $xxxx-$yyyy   String constants (immediately after variables)

Bank 1 (Code)
  $0000-$xxxx   Module code (loaded by emulator)
```

The emulator loads `.816` modules into bank 1 at the current load address.
Global variables and string data are placed at `$1000` in bank 0.
The static base register (SB = R8) is initialised to `$1000` at module entry.

## 2. Processor Mode

The compiler operates the 65C816 in **native mode** (not 6502 emulation mode).
The module entry point switches to native mode immediately:

```
CLC             ; Clear carry for XCE
XCE             ; Exchange carry and emulation bit -> native mode
REP #$30        ; 16-bit accumulator and index registers
```

After this point, the processor runs with 16-bit A, X, and Y registers.
The compiler tracks the current accumulator width (`longa`) and index
width (`longi`) and emits REP/SEP instructions only when a mode change
is actually needed.

**Statement boundaries**: At the start of every statement, the compiler
forces 16-bit mode via `Set16(1, 1)`. This is required because any
statement may be a branch target, and the processor mode must be known
at every point in the code.

## 3. Register File

The first 18 bytes of the direct page serve as a virtual register file.
Each register is 16 bits (2 bytes):

```
Address   Register   Purpose
$00-$01   R0         General purpose / first parameter / return value
$02-$03   R1         General purpose / second parameter
$04-$05   R2         General purpose / third parameter
$06-$07   R3         General purpose
$08-$09   R4         General purpose
$0A-$0B   R5         General purpose
$0C-$0D   R6         General purpose
$0E-$0F   R7         General purpose
$10-$11   R8 (SB)    Static Base - points to module global variable area
```

**Register allocation** uses a simple stack model tracked by the `RH`
(register high-water) variable. Registers are allocated from R0 upward.
At each statement boundary, RH must be 0 (all registers free). If not,
the compiler reports a "Reg Stack" error.

The maximum register count is 8 (R0-R7). SB is reserved and never
allocated for temporaries.

### A, X, Y Registers

The hardware A register is used as a transfer register for all operations.
Values move between the register file and memory through A:

```
LDA DirectPage, $00     ; Load R0 into A
STA StackRelative, 5    ; Store A to stack offset 5
```

X and Y are used as index registers:
- **Y**: Used for global variable access via `(SB),Y` addressing
- **X**: Used for array element access via `base,X` addressing

## 4. Stack Frame

The 65C816 hardware stack is used for procedure call frames. There is
no separate frame pointer - all local access is via stack-relative
addressing with compile-time-known offsets.

### Frame Layout

After `ORG_Enter`, the stack looks like:

```
High addresses (before call)
  +-----------------------+
  | Return address (2/3B) |  <- pushed by JSR/JSL
  +-----------------------+
  | Parameter N           |  \
  | ...                   |   } Parameter block (parblksize bytes)
  | Parameter 1           |  /
  +-----------------------+
  | Local var M           |  \
  | ...                   |   } Local block (locblksize bytes)
  | Local var 1           |  /
  +-----------------------+  <- S (stack pointer after frame allocation)
Low addresses
```

**Frame allocation** in `ORG_Enter`:
```
TSC                     ; Transfer S to A
SEC                     ; Set carry for subtraction
SBC #frame_size         ; Subtract total frame size
TCS                     ; Transfer A back to S
```

**Frame deallocation** in `ORG_Return`:
```
TSC                     ; Transfer S to A
CLC                     ; Clear carry for addition
ADC #frame_size         ; Add total frame size (deallocate)
TCS                     ; Transfer A back to S
RTS                     ; Return (or RTL for exported procedures)
```

### Parameter Storage

Parameters arrive in virtual registers (R0, R1, R2, ...) and are
immediately stored to their stack locations by `ORG_Enter`. The
register count per parameter depends on its type:

| Parameter kind               | Registers | Stack bytes | Content                    |
|------------------------------|-----------|-------------|----------------------------|
| Value (INTEGER, CHAR, etc.)  | 1         | 2           | Value                      |
| Value (BYTE, BOOLEAN)        | 1         | 1           | Value (8-bit)              |
| VAR parameter                | 2         | 4           | 16-bit addr + 16-bit bank  |
| Open array value             | 2         | 4           | 16-bit addr + 16-bit bank  |
| VAR open array               | 3         | 6           | 16-bit addr + 16-bit bank + 16-bit length |

After storing parameters, `RH` is reset to 0 - all registers are free
for use by the procedure body.

### Local Variable Access

Local variables and parameters are accessed via stack-relative addressing:

```
LDA offset,S            ; Load local/parameter from stack
STA offset,S            ; Store to local/parameter on stack
```

The offset is a compile-time constant computed from the variable's
position within the frame. The `frame` variable tracks additional
stack depth from SaveRegs/RestoreRegs during procedure calls within
the body.

### Global Variable Access

Global variables are accessed indirectly through the SB register using
direct-page-indirect-indexed-Y addressing:

```
LDY #offset             ; Load variable offset into Y
LDA (SB),Y              ; Load from *(SB + offset) = *(0x1000 + offset)
```

For stores:
```
LDA DirectPage, reg     ; Load value from virtual register
LDY #offset             ; Load variable offset
STA (SB),Y              ; Store to *(SB + offset)
```

## 5. Calling Convention

### Caller Side

1. **PrepCall**: Save any live registers (R0..RH-1) to the hardware stack:
   ```
   LDA $00              ; Push R0
   PHA
   LDA $02              ; Push R1
   PHA
   ...
   ```
   The `frame` variable is increased by `2 * saved_register_count`.

2. **Evaluate arguments**: Each argument is evaluated and left in
   consecutive registers starting from R0.

3. **Call**: Issue the call instruction:
   - **Local procedure** (same module): `JSR address` (3 bytes)
   - **Exported/imported procedure** (cross-module): `JSL address` (4 bytes)

4. **After return**: If the procedure has a return value, it is in R0.
   Restore saved registers from the stack (reverse order):
   ```
   PLA
   STA $02              ; Restore R1
   PLA
   STA $00              ; Restore R0
   ```
   The return value register is adjusted to account for the restored
   register positions.

### Callee Side

1. **ORG_Enter**: Allocate the stack frame (TSC/SEC/SBC/TCS), then
   store parameters from registers to their stack slots.

2. **Procedure body**: Execute statements. All register file slots
   are available (RH starts at 0).

3. **ORG_Return**:
   - If a function: `load(x)` places the return value in R0.
   - Deallocate the stack frame (TSC/CLC/ADC/TCS).
   - `RTS` for local procedures, `RTL` for exported procedures.

### Interrupt Procedures

Interrupt procedures (`PROCEDURE*`) use a slightly different entry/exit:
- Entry: No TSC (the processor has already saved state), just SBC/TCS
- Exit: CLC/ADC/TCS then `RTI` (Return from Interrupt)

## 6. Addressing Patterns

### Item Modes

The code generator uses an `Item` struct to represent values during
compilation. Each Item has a `mode` that determines how it is accessed:

| Mode       | Value | Meaning                         | Key fields                 |
|------------|-------|---------------------------------|----------------------------|
| `Const`    | 1     | Compile-time constant           | `a`=value                  |
| `Var`      | 2     | Variable in memory              | `a`=offset, `r`=level      |
| `Par`      | 3     | VAR parameter (indirect)        | `a`=stack offset of pointer |
| `Reg`      | 10    | Value in virtual register       | `r`=register number        |
| `RegI`     | 11    | Register indirect with offset   | `r`=register, `a`=offset   |
| `Cond`     | 12    | Boolean condition (branch code) | `r`=condition, `a`/`b`=fixup chains |

The `r` field for `Var` mode indicates the scope level:
- `r > 0`: Local variable (stack-relative access)
- `r == 0`: Global variable (SB-indirect access)
- `r < 0`: Imported from another module

### Load Patterns

**Constant** (mode=Const):
```
; 16-bit constant
LDA #value              ; Immediate load
STA $reg                ; Store to virtual register

; 8-bit constant (BYTE/CHAR/BOOL)
SEP #$20                ; 8-bit accumulator
LDA #value
STA $reg
REP #$20                ; Back to 16-bit
```

**Global variable** (mode=Var, r=0):
```
LDY #offset             ; Variable offset from SB
LDA ($10),Y             ; Load via SB indirect indexed Y
STA $reg                ; Store to virtual register
```

**Local variable** (mode=Var, r>0):
```
LDA offset,S            ; Stack-relative load
STA $reg                ; Store to virtual register
```

**VAR parameter** (mode=Par) - dereference through 4-byte pointer:
```
LDA ptr_offset,S        ; Load 16-bit address from stack
STA $reg0
LDA ptr_offset+2,S      ; Load bank byte from stack
STA $reg1
LDA [$reg0]             ; Dereference through 24-bit pointer
STA $reg0               ; Result overwrites address register
```

**Register indirect** (mode=RegI) - array element or record field:
```
; With zero offset:
LDA ($reg)              ; Direct page indirect

; With non-zero offset:
LDY #offset             ; Load field/element offset
LDA ($reg),Y            ; Direct page indirect indexed Y
STA $reg                ; Store result back
```

### Store Patterns

**To local variable**:
```
LDA $src_reg            ; Load from source register
STA offset,S            ; Store to stack location
```

**To global variable**:
```
LDA $src_reg            ; Load from source register
LDY #offset             ; Variable offset
STA ($10),Y             ; Store via SB indirect indexed Y
```

**To register indirect** (array element):
```
LDA $src_reg            ; Load value
LDX $addr_reg           ; Load base address into X
STA base,X              ; Store with absolute indexed X
```

### Address Calculation (loadAdr)

Used when passing variables by reference (VAR parameters).

**Global variable address**:
```
LDA #offset             ; Variable offset
ADC $10                 ; Add SB (static base)
STA $reg0               ; Low 16 bits of address
LDA #0
PHB                     ; Push data bank register
PLA                     ; Pull into A (bank byte)
STA $reg1               ; High 16 bits (bank)
```

This produces a 4-byte (two-register) pointer: address + bank.

## 7. Type Sizes

| Oberon Type    | Form      | Size (bytes) | Notes                          |
|----------------|-----------|--------------|--------------------------------|
| BOOLEAN        | Bool      | 1            | 0=FALSE, non-zero=TRUE         |
| BYTE           | Int       | 1            | Unsigned 8-bit                 |
| CHAR           | Char      | 1            | 8-bit ASCII                    |
| INTEGER        | Int       | 2            | 16-bit signed (1 WordSize)     |
| LONGINT        | Int       | 4            | 32-bit signed (2 WordSize)     |
| REAL           | Real      | 4            | 32-bit IEEE 754 float          |
| SET            | Set       | 4            | 32-bit bitfield                |
| POINTER        | Pointer   | 4            | 16-bit address + 16-bit bank   |
| NIL            | NilTyp    | 2            |                                |
| ARRAY          | Array     | len * base   | Contiguous elements            |
| RECORD         | Record    | sum of fields| Fields at computed offsets      |

**WordSize = 2 bytes** is the fundamental unit. Pointers are 2 * WordSize
to accommodate the 65C816's 24-bit address space (16-bit address within
a 64KB bank, plus the bank byte).

### Type Width and Processor Mode

For 1-byte types (BOOLEAN, BYTE, CHAR), the compiler switches the
accumulator to 8-bit mode before loads and stores:

```
SEP #$20                ; Set 8-bit accumulator (M flag)
LDA source              ; 8-bit load
STA dest                ; 8-bit store
REP #$20                ; Restore 16-bit accumulator
```

For 2-byte types (INTEGER), the standard 16-bit mode is used.

## 8. Branching and Control Flow

### Condition Codes

Comparisons set condition codes in the Item's `r` field:

| Code | Value | Meaning            | 65C816 flag test           |
|------|-------|--------------------|----------------------------|
| MI   | 0     | Minus              | N=1                        |
| EQ   | 1     | Equal              | Z=1                        |
| LT   | 5     | Less than (signed) | V xor N                    |
| LE   | 6     | Less or equal      | Z=1 or (V xor N)          |
| AL   | 7     | Always             | Unconditional              |
| PL   | 8     | Plus               | N=0                        |
| NE   | 9     | Not equal          | Z=0                        |
| GE   | 13    | Greater or equal   | not(V xor N)               |
| GT   | 14    | Greater than       | Z=0 and not(V xor N)      |
| NV   | 15    | Never              | No branch                  |

Each condition has a negation obtained by XOR with 8 (e.g. EQ(1) <-> NE(9)).

### Unsigned Comparisons

For BYTE-sized operands or unsigned comparisons, the compiler uses
the carry flag directly:

| Condition | Branch instruction |
|-----------|--------------------|
| LT        | BCS (branch carry set = borrow) |
| GE        | BCC (branch carry clear = no borrow) |

### Signed Comparisons (INTEGER)

Signed 16-bit comparisons on the 65C816 require checking the overflow
flag (V) to determine the true relationship. The compiler generates a
multi-instruction sequence:

```
; Example: Branch if Less Than (signed)
BVS INVERT          ; If overflow, meaning is inverted
BMI TO_TARGET       ; No overflow + negative = truly less than
BRA SKIP            ; No overflow + positive = not less than
INVERT:
BPL TO_TARGET       ; Overflow + positive = actually less than
BRA SKIP            ; Overflow + negative = actually not less than
TO_TARGET:
BRL target          ; Single fixup point for the branch
SKIP:               ; Fall through
```

This pattern ensures a single fixup point (the BRL) regardless of
which flag combination triggers the branch.

### Forward Branch Fixups

Forward branches use a fixup chain. When a forward branch is emitted,
the 2-byte offset field of the BRL instruction stores a link to the
previous branch in the same chain (0 = end of chain).

When the target is reached, `ORG_FixLink` walks the chain and patches
each BRL with the correct offset:

```c
while (L != 0) {
    next = code[L] | (code[L+1] << 8);   // Read chain link
    fix(L, target_pc);                     // Patch to actual target
    L = next;                              // Follow chain
}
```

The `fix()` function also optimises short branches: if the offset fits
in a signed byte (-128..+127), BRL ($82, 3 bytes) is replaced with
BRA ($80, 2 bytes) and the spare byte becomes NOP ($EA).

### Backward Branches

Backward branches (WHILE, REPEAT loops) use direct PC-relative addressing
since the target address is already known:

```
BRA target              ; Short backward branch (2 bytes)
; or
BRL target              ; Long backward branch (3 bytes)
```

### Boolean Short-Circuit Evaluation

The `Cond` item mode carries two fixup chains:
- `a`: Chain of branches taken when the condition is FALSE
- `b`: Chain of branches taken when the condition is TRUE

For `&` (AND): If the left operand is FALSE, skip the right operand
entirely (short-circuit). The FALSE chain of the left operand is
propagated.

For `OR`: If the left operand is TRUE, skip the right operand. The
TRUE chain of the left operand is propagated.

## 9. Arithmetic Code Generation

### Integer Addition/Subtraction

```
LDA $reg_left           ; Load left operand
CLC                     ; Clear carry (for ADC)
ADC $reg_right          ; Add right operand
STA $reg_result         ; Store result
```

For subtraction, SEC/SBC instead of CLC/ADC.

### Constant optimisation

When adding/subtracting a constant, the compiler uses immediate mode:
```
LDA $reg
CLC
ADC #constant
STA $reg
```

### Multiplication

For power-of-2 multiplication, the compiler uses shifts:
```
LDA $reg                ; Load value
ASL A                   ; Shift left (multiply by 2)
ASL A                   ; Again (multiply by 4)
STA $reg
```

For variable shift counts:
```
LDX #count              ; Load shift count
loop:
ASL $reg                ; Shift left
DEX
BNE loop
```

General multiplication (non-power-of-2) is not yet implemented
as a native instruction sequence and requires a runtime routine.

### Division

Integer division by powers of 2 uses right shifts with sign handling.
General division requires a runtime routine (not yet implemented).

## 10. Jump Types: JSR vs JSL

A key design decision: **JSR within a module, JSL between modules**.

| Call type          | Instruction | Size | Return  | Address bits |
|--------------------|-------------|------|---------|--------------|
| Local procedure    | JSR abs     | 3    | RTS (1) | 16-bit       |
| Exported procedure | JSL long    | 4    | RTL (1) | 24-bit       |
| Imported procedure | JSL long    | 4    | RTL (1) | 24-bit       |

Within a single module, all code resides in the same 64KB bank, so
16-bit JSR is sufficient and saves one byte per call. Cross-module
calls use JSL which pushes the full 24-bit return address (including
the program bank register).

The decision is made at call time based on the procedure's scope:
- `x->r >= 0` and `x->b == 0`: Local procedure -> JSR
- `x->r < 0` (imported) or `x->b == 1` (exported): -> JSL

JSL addresses are recorded in the relocation table for the loader
to fix up at load time.

## 11. Relocation

The compiler generates code with addresses relative to the start of the
module (base address 0). The loader adjusts these at load time.

### Relocation Table

During code generation, every JSL instruction's address is recorded:
```c
reloc[relocC++] = ORG_pc;    // Record position of JSL operand
```

The relocation table is stored in the `.816` object file and processed
by the loader.

### Loader Relocation

The emulator's `loadMod` function applies relocations:

1. For **JSR** ($20): Add module base to the 16-bit operand
2. For **JSL** ($22): Add module base to the 16-bit operand and set
   the bank byte to the module's bank number

```
Original:  JSL $0045           ; Relative to module start
Relocated: JSL $01:0045        ; Absolute in bank 1 at offset $0045
```

### Future: Inter-Module Fixups

The object file also contains `fixorgP`, `fixorgD`, and `fixorgT`
fields for procedure, data, and type descriptor fixups between modules.
These are not yet fully implemented.

## 12. Object File Format (.816)

The `.816` binary file has the following structure:

```
+---------------------------+
| Module name (string, NUL) |
| Key (4 bytes)             |
| Version (1 byte)          |
| Size (4 bytes)            |
+---------------------------+
| Import list:              |
|   Module name (string)    |
|   Key (4 bytes)           |
|   ... repeat ...          |
|   NUL byte (end)          |
+---------------------------+
| Type descriptor size (4B) |
| Type descriptors (N * 4B) |
+---------------------------+
| Variable size (4 bytes)   |  (uninitialized, not stored)
+---------------------------+
| String size (4 bytes)     |
| String data (N bytes)     |
+---------------------------+
| Code size (4 bytes)       |
| Code data (N bytes)       |
+---------------------------+
| Export procedures:         |
|   Name (string)           |
|   Address (4 bytes)       |
|   ... repeat ...          |
|   NUL byte (end)          |
+---------------------------+
| Number of exports (4B)    |
| Entry point (4 bytes)     |
| Export values (N * 4B)    |
+---------------------------+
| Pointer list (N * 4B)     |
| -1 marker (4 bytes)       |
+---------------------------+
| fixorgP (4 bytes)         |
| fixorgD (4 bytes)         |
| fixorgT (4 bytes)         |
+---------------------------+
| Relocation count (4B)     |
| Reloc addresses (N * 4B)  |
+---------------------------+
| Entry point (4 bytes)     |
| 'O' marker (1 byte)       |
+---------------------------+
```

The loader reads the entry point from the end of the file (4 bytes
before the final 'O' marker) and then processes sections sequentially.

### Loading Sequence

1. Read header (name, key, version, size)
2. Skip imports
3. Skip type descriptors
4. Read variable size (allocate space at MODULE_VAR_BASE)
5. Read string data, load at MODULE_VAR_BASE + var_size
6. Read code, load into bank 1 at current load address
7. Skip export sections
8. Read fixup information
9. Process relocation table (adjust JSR/JSL addresses)
10. Jump to entry point via JSL

## 13. Module Entry Point

Every module begins execution at the entry point generated by
`ORG_Header`:

```
CLC                     ; Prepare for XCE
XCE                     ; Switch to native mode
REP #$30                ; 16-bit A, X, Y
LDA #$1000              ; Static base address
STA $10                 ; Store to SB (R8)
; ... module body (BEGIN section) ...
RTL                     ; Return to loader/caller
```

The emulator calls this entry point with JSL, so the module returns
with RTL.

## 14. Design Decisions and Rationale

### Why direct page registers instead of a register file in RAM?

Direct page addressing on the 65C816 uses 2-byte instructions instead
of 3-byte absolute addressing. Since the register file is the most
frequently accessed memory, placing it at $00-$11 saves one byte per
register access and is one cycle faster.

### Why no frame pointer?

The 65C816's stack-relative addressing mode (`offset,S`) provides
direct access to any byte on the stack with a compile-time offset.
This eliminates the need for a dedicated frame pointer register,
saving setup/teardown instructions at every procedure call.

### Why JSR within modules, JSL between?

A single module's code fits within one 64KB bank, so 16-bit addressing
is sufficient. JSR is one byte shorter than JSL and one cycle faster.
Cross-module calls require the full 24-bit address to reach code in
different banks.

### Why parameters in registers then stored to stack?

This follows the original Oberon compiler's design where parameters
are prepared in a register bank and then copied to the callee's frame.
On the 65C816, the virtual register file serves this role. The
alternative (pushing parameters directly to the stack) would require
the caller to know the callee's frame layout.
