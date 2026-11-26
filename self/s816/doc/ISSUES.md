# Oberon 65C816 Compiler - Known Issues

## Resolved Bugs

| ID | Summary | Fix |
|----|---------|-----|
| BUG-1 | PutNum / procedure parameter expression bug | Fixed: parameter/expression handling in ORG.c |
| BUG-2 | FOR loop used CMP instead of SEC+SBC | Fixed: ORG_For1() now uses SEC+SBC like IntRelation |
| BUG-3 | VAR parameter store wrote to stack slot not through pointer | Fixed: ORG_Store() Par case uses indirect store |
| BUG-4 | CopyString / string assignment broken | Fixed: loadStringAdr computes address with CLC+ADC |
| BUG-5 | DIV/MOD missing for variable operands | Fixed: inline repeated-subtraction loop in ORG_Op() |
| BUG-6 | StringTest SEP missing for last PutChar | Fixed: SEP/REP management for BYTE loads |
| BUG-7 | StoreStruct not implemented | Fixed: block copy loop implemented |
| BUG-8 | emitBranch LE: BEQ jumped to SKIP instead of TO_TARGET | Fixed: offset `+13` → `+10` in case LE. Caused Out.Int leading space bug (WHILE n > i entered loop when n=i) |
| BUG-9 | Boolean expressions not materialized to values | Fixed: added Cond→value materialization in `load()` (ORG.c:532). Emits `emitBranch(negated)`, LDA #1 / LDA #0, STA reg. Also fixed `loadCond()` to set `orig_type` so `emitBranch` doesn't crash on boolean-origin Cond items. Tests fixed: L1_Comparison, L1_SignedCompare. L1_Boolean still has separate NOT/OR logic bugs. |
| BUG-12 | BYTE/CHAR to INTEGER promotion — upper byte garbage | Fixed: restructured all 4 byte-load paths in `load()` (ORG.c) to zero-extend. Pattern: Set8→LDA→Set16→AND #$00FF→STA (16-bit). Previously the STA was done in 8-bit mode, leaving upper byte as garbage. Tests fixed: L1_CharType. L1_ByteType/L1_TypeConvert still have separate BYTE arithmetic bugs. |
| BUG-10 | Power-of-2 multiply infinite loop | Fixed: BNE in ASL/DEX/BNE shift loop branched back to LDX (which reloaded the shift count), creating an infinite loop. Used `loop_top` variable to capture address of ASL before emitting loop body. Both power-of-2 paths fixed in `ORG_MulOp()`. Tests fixed: L1_Multiply. |
| BUG-11 | General multiply stores result to wrong register | Fixed: In `ORG_MulOp()`, the STA storing the multiply result used x->r BEFORE the `RH--; x->r = RH-1` update. When a function call in the right operand caused register reordering (x->r > y->r), the result was stored to the old register but subsequent code read from the new (wrong) register. Fix: moved STA after the RH/x->r update. All three general multiply paths fixed. Tests fixed: L1_Recursion (Fact(5) now correctly returns 120). |
| BUG-14 | VAR parameters — two bugs | Fixed: (1) `ORG_Store` for `ORB_Par` mode stored value directly to stack pointer slots instead of through the pointer. Replaced with: load 3-byte pointer from stack into temp DP regs, then `STA [$temp]` (indirect long). (2) `ORG_VarParam` for global variables used `LDA (SB),Y` which loads the VALUE, not the ADDRESS. Replaced with `LDA SB; CLC; ADC #offset` to compute the address. Tests fixed: L1_VarParams. |
| BUG-15 | Boolean expressions crash compiler / produce wrong code | Fixed: Three problems in `emitBranch()` and `ORG_And2()`/`ORG_Or2()`: (1) `And2`/`Or2` didn't propagate `orig_type` from the right operand, so signed comparison conditions (GT, LE, etc.) were handled by unsigned branch patterns when mixed with boolean operators. (2) Unsigned branch paths for LT, GE, LE in `emitBranch()` used BCS/BCC directly with Fixup mode, which called `of()` (stores relative 1-byte chain offset) instead of `ofl()` (stores absolute 2-byte address). `ORG_FixLink()` expects absolute addresses, so the chain got corrupted, causing either a compiler crash (SIGBUS) or corrupted generated code. (3) The BCS/BCC instructions in unsigned LT and GE paths were swapped (BCS for LT, BCC for GE — should be opposite). Fix: all unsigned paths now use skip+BRL pattern (consistent with EQ/NE/signed paths), BCS/BCC corrected, and `orig_type` propagated in `And2`/`Or2`. Tests fixed: L1_Boolean. |
| BUG-13 | SYSTEM.GET/PUT — Reg Stack error and wrong width | Fixed: Two problems: (1) `ORG_Get()` and `ORG_Put()` used custom inline code that didn't properly manage register allocation (leaving RH=1) and always used 8-bit mode for stores. Rewrote both to follow the original Oberon pattern: `load(x); x->type = y->type; x->mode = RegI; x->a = 0; ORG_Store(dest, src)`. This delegates register management and type-width handling to the existing Store infrastructure. (2) `load()` for RegI mode had no type-size-aware accumulator width setting, so it used whatever width was previously active. Added Set8+zero-extend for size==1, Set16 for size>1. Tests fixed: L1_SystemGet. |
| BUG-16 | BYTE arithmetic produces wrong results | Fixed: All arithmetic paths in `ORG_AddOp()` had guard `x->type->form == ORB_Int && x->type->size == 2` which excluded BYTE (size==1). Since `load()` already zero-extends BYTE values to 16-bit in registers, the size check was wrong — the 16-bit arithmetic works correctly for both INTEGER and BYTE operands. Removed `&& ...size == 2` from all 5 conditions (3 addition paths, 2 subtraction paths). Tests fixed: L1_ByteType, L1_TypeConvert. All 30 L1 tests now pass. |


## Current Bugs

No known bugs. All 30 Level 1 tests pass.


## Unimplemented Features

### FEAT-1: Numeric CASE Statement
**Test**: `test/CaseTest.Mod`, `test/SimpleCaseTest.Mod`
**Status**: Skipped in test suite
**Notes**: CASE on INTEGER/CHAR not implemented. Only type CASE partially works.

### FEAT-2: PACK/UNPK
**Test**: `test/PackTest.Mod`
**Status**: Skipped in test suite
**Notes**: REAL number packing/unpacking.

### FEAT-3: SET Operations - Subset, INCL/EXCL, Range Sets
**Test**: `test/SetOperationsTest.Mod`
**Status**: Skipped in test suite
**Notes**: IN, IS, set range constructor `{a..b}`, INCL, EXCL not implemented.

### FEAT-4: Pointers and NEW
**Notes**: Pointer dereferencing (DeRef), NEW allocation not implemented.

### FEAT-5: Type Guards and Type CASE
**Notes**: IS operator, type testing, type CASE not implemented.

### FEAT-6: Standard Functions
**Notes**: ABS, ODD, FLOOR not fully implemented.

### FEAT-7: REAL / Float
**Notes**: Floating point not implemented.

### FEAT-8: String Comparison
**Notes**: StringRelation not implemented. Cannot compare strings with
`=`, `#`, `<`, etc.


## Priority Order for Fixing Bugs

None — all known bugs are resolved.
