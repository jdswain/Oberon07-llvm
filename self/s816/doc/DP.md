# Direct Page Layout

The 65C816 Direct Page (DP) is the primary working memory for the Oberon
compiler's generated code. This document describes the full DP layout and
the rules for assembly routines that interoperate with Oberon modules.

## Memory Map

```
Address   Name         Description
-------   ----------   ------------------------------------
$00-$01   (scratch)    The code generator's, within one statement (a far store's temp)
$02-$03   R[0]         General register / 1st parameter / return value
$04-$05   R[1]         General register / 2nd parameter
$06-$07   R[2]         General register / 3rd parameter
$08-$09   R[3]         General register / 4th parameter
$0A-$0B   R[4]         General register / 5th parameter
$0C-$0D   R[5]         General register / 6th parameter
$0E-$0F   R[6]         General register
$10-$11   R[7]         General register
$12-$13   R[8]         General register
$14-$15   R[9]         General register
$16-$17   R[10]        General register
$18-$19   R[11]        General register
$1A-$1B   R[12]        General register
$1C-$1D   R[13]        General register
$1E-$1F   R[14]        General register
$20-$21   SB_TEMP      Temp for imported module var_base
$22-$23   FP_A_LO      FP workspace: operand A low word
$24-$25   FP_A_HI      FP workspace: operand A high word
$26-$27   FP_B_LO      FP workspace: operand B low word
$28-$29   FP_B_HI      FP workspace: operand B high word
$2A-$2B   FP_SIGN      FP workspace: result sign
$2C-$2D   FP_EXP       FP workspace: working exponent
$2E-$2F   FP_M1_LO     FP workspace: mantissa 1 low
$30-$31   FP_M1_HI     FP workspace: mantissa 1 high
$32-$33   FP_M2_LO     FP workspace: mantissa 2 low
$34-$35   FP_M2_HI     FP workspace: mantissa 2 high
$36-$37   FP_PROD0     FP workspace: product word 0
$38-$39   FP_PROD1     FP workspace: product word 1
$3A-$3B   FP_PROD2     FP workspace: product word 2
$3C-$3D   FP_TEMP      FP workspace: scratch
$3E-$3F   FP_TEMP2     FP workspace: scratch
$40-$41   FP_CNT       FP workspace: loop counter
$42-$43   SB           Static Base — module variable area pointer
$44-$45   BANK_DP      Own module's data bank byte: with SB, the 24-bit pointer [SB]
$46-$FF   (unused)     Available for future DP use
$0100-$0845            Hardware stack (2K, SP init to $0845)
```

All registers and workspace entries are 16-bit (2 bytes), stored
little-endian as per 65C816 convention.

## Static Base ($42-$43) and BANK_DP ($44-$45)

SB points to the current module's global variable area, and BANK_DP
holds its bank: the three bytes $42-$44 are a 24-bit pointer. Both are
set by the module's initialisation and by every exported procedure's,
method's and procedure variable's entry, and put back when it returns.

Global variable access uses `[SB],Y` long indirect indexed addressing,
where Y holds the variable's offset within the module data area, so a
module's variables may be in any bank (.816 version 4; OS16's loader
puts them above bank 0). An imported module's variables are reached in
the same way through SB_TEMP: its base at $20-$21 and its bank at $22.
The data bank register stays 0.

**SB is never saved or restored by the compiler's calling convention.**
Any code that overwrites $42-$45 will corrupt all subsequent global
variable access.

## Register File ($02-$1F)

The compiler maintains 15 general-purpose registers R[0] through R[14].
Register allocation uses a stack model tracked by the `RH` (Register High)
variable. Registers are allocated from R[0] upward. At statement boundaries,
RH is always 0 (all registers free).

Parameters are passed in R[0], R[1], R[2], etc. Function results are
returned in R[0].

Pointer and REAL types occupy two consecutive registers (4 bytes total):
the low word in R[n] and the high word (bank byte for pointers, upper
IEEE bits for REAL) in R[n+1].

## SB_TEMP ($20-$22)

Used by the compiler's code generator when accessing variables from
imported modules. The import's variable base address is loaded into
SB_TEMP and its bank into $22 (SB_TEMP_BANK, over FP_A_LO), then
`[SB_TEMP],Y` is the access. This is a
transient value that exists only within a single generated instruction
sequence.

At runtime during an external call (JSL), SB_TEMP is not in use and
may be freely overwritten.

## FP Workspace ($22-$41)

The floating-point workspace is used by the compiler's built-in FP
subroutines (FADD, FMUL, FDIV, FCMP, FLT, FLOOR). These subroutines
are emitted at the end of each module's code section and called via
intra-module JSR — they are never active across inter-module JSL calls.

At runtime during an external call (JSL), the FP workspace is not in
use and may be freely overwritten.

## Calling Convention: What Happens Around JSL

When Oberon code calls an external procedure via JSL:

1. **SaveRegs**: The compiler pushes R[0] through R[RH-1] onto the
   hardware stack (PHA for each register, low to high).
2. **Load parameters**: R[0], R[1], ... are loaded with the call's
   arguments.
3. **JSL**: Control transfers to the external procedure.
4. The external procedure executes and returns via RTL.
5. **RestoreRegs**: The compiler pops R[RH-1] through R[0] from the
   stack, overwriting whatever the callee left in those DP locations.

**What SaveRegs saves:** Only R[0] through R[RH-1] — the registers
that were in use at the call site.

**What SaveRegs does NOT save:** SB ($42), SB_TEMP ($20), FP workspace
($22-$41). These are either persistent (SB) or transient and not active
across calls (SB_TEMP, FP workspace).

## Rules for Assembly Routines

Assembly modules called from Oberon via JSL must follow these rules:

### Safe to use freely

| Region | Addresses | Notes |
|--------|-----------|-------|
| R[0]-R[14] | $02-$1F | Caller has saved any in-use values via SaveRegs. Restored on return. |
| SB_TEMP | $20-$21 | Not active during external calls. |
| FP workspace | $22-$41 | Not active during external calls. |

This gives **32 words** (64 bytes) of contiguous DP workspace from $02
through $41 available to assembly, plus $00-$01; SB and BANK_DP at
$42-$45 must be preserved.

### Must preserve

| Region | Addresses | Notes |
|--------|-----------|-------|
| SB, BANK_DP | $42-$45 | Never saved by calling convention. Corruption breaks all global variable access in the calling module. |

### Interaction with sub-calls

If an assembly routine calls other routines (e.g., SetPixel from
DrawLine), those sub-calls will clobber whichever DP registers they
use. The assembly routine must account for this by keeping its
persistent state in registers that the sub-call does not touch.

For example, SetPixel uses R[0]-R[7] ($02-$11). A caller that needs
persistent state across SetPixel calls should store it in R[8]-R[14]
($12-$1F) or the FP workspace ($22-$41).

### Parameters and return values

- Parameters arrive in R[0], R[1], R[2], etc.
- Pointer/REAL parameters occupy two consecutive registers.
- Function results must be placed in R[0] before RTL.
- BYTE-typed return values should be a clean 16-bit value (zero in the
  high byte) since the caller may read the full 16-bit register.

### Processor mode

Assembly routines are entered with 16-bit accumulator and 16-bit index
registers (M=0, X=0). They must return in the same mode. Temporary
switches to 8-bit mode (SEP #$20) for byte operations are fine as long
as REP #$20 restores 16-bit mode before RTL.
