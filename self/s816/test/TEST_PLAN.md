# Oberon Compiler Test Suite — Completion Roadmap

This test suite is organized by language feature, ordered by dependency.
Each level builds on the previous. Failing tests serve as the implementation TODO list.

## Design Principles

- Each test covers **one language feature** and produces verifiable UART output
- Tests are ordered by dependency — foundational features first
- Every test gets a `.expected` file so failures are immediately visible
- Tests that fail become the implementation TODO list
- A common output pattern (PutChar/PutString/PutInt/NewLine via SYSTEM.PUT)
  is repeated per-module since multi-module import isn't yet working

## Test Naming Convention

Tests are named `L<level>_<Feature>.Mod` where the level indicates the
dependency tier. All tests within a level are independent of each other.

---

## Level 0: Legacy / Integration Tests - Done

Pre-existing tests that exercise multiple language features together.

| Test | Feature | Notes |
|------|---------|-------|
| `L0_Bresenham.Mod` | Bresenham line drawing (loops, arithmetic, SYSTEM.PUT/GET) | |
| `L0_DivMod.Mod` | DIV and MOD with variables, constants, power-of-2 | |
| `L0_ForLoopRun.Mod` | FOR loop with Out.Int output | |
| `L0_ImportVar.Mod` | Imported variable access (depends on ExportVar) | |
| `L0_OutTest.Mod` | Out module: Char, Hex, Bool, Ln | |
| `L0_RuntimeTest.Mod` | Runtime module: Mul, Div, Mod (depends on Runtime) | |
| `L0_StringCopyRun.Mod` | String assignment and Out.String | |
| `L0_TestTest.Mod` | TestTool module: PutChar, NewLine (depends on TestTool) | |

## Level 1: Foundations - Complete

Core language features that everything else depends on.

| Test | Feature | Notes |
|------|---------|-------|
| `L1_ModuleEmpty.Mod` | Empty module compiles and runs | |
| `L1_GlobalVar.Mod` | Global INTEGER variable assignment | |
| `L1_Constants.Mod` | CONST declarations (integer, hex, char) | |
| `L1_AddSub.Mod` | `+`, `-` on integers (const and variable) | |
| `L1_Negate.Mod` | Unary minus on integers | |
| `L1_Multiply.Mod` | `*` with constants, power-of-2, variable*variable, negatives | |
| `L1_Divide.Mod` | `DIV` with constants and variables, negative dividend/divisor | |
| `L1_Modulo.Mod` | `MOD` with constants and variables, negative cases | |
| `L1_Comparison.Mod` | `=`, `#`, `<`, `<=`, `>`, `>=` on integers | |
| `L1_SignedCompare.Mod` | Comparisons with negative values | |
| `L1_Boolean.Mod` | `&`, `OR`, `~` and short-circuit evaluation | |
| `L1_IfElse.Mod` | IF / ELSIF / ELSE | |
| `L1_WhileLoop.Mod` | WHILE loop | |
| `L1_RepeatLoop.Mod` | REPEAT / UNTIL | |
| `L1_ForLoop.Mod` | FOR / TO / DO | |
| `L1_ForBy.Mod` | FOR with BY clause (step 2, step -1) | |
| `L1_Procedure.Mod` | Procedure declaration and call | |
| `L1_Function.Mod` | Function procedure with RETURN | |
| `L1_LocalVars.Mod` | Local variables in procedures | |
| `L1_ValueParams.Mod` | Value parameters (INTEGER, CHAR, BOOLEAN) | |
| `L1_VarParams.Mod` | VAR parameters | |
| `L1_NestedProc.Mod` | Nested procedure definitions | |
| `L1_Recursion.Mod` | Recursive function (factorial) | |
| `L1_ByteType.Mod` | BYTE type, assignment, arithmetic | |
| `L1_CharType.Mod` | CHAR type, CHR(), ORD() | |
| `L1_TypeConvert.Mod` | BYTE<->INTEGER promotion/truncation | |
| `L1_SystemPut.Mod` | SYSTEM.PUT for UART output | |
| `L1_SystemGet.Mod` | SYSTEM.GET to read memory | |
| `L1_Bitwise.Mod` | AND(), ORA(), EOR() builtins | |
| `L1_Shift.Mod` | ASL(), LSR(), ROL() builtins | |

## Level 2: Arrays and Strings - Done

| Test | Feature | Notes |
|------|---------|-------|
| `L2_FixedArray.Mod` | Global ARRAY OF INTEGER — init, index, read | |
| `L2_LocalArray.Mod` | Local array in procedure (stack-based) | |
| `L2_ArrayParam.Mod` | Array as value parameter | |
| `L2_ArrayVarParam.Mod` | Array as VAR parameter | |
| `L2_OpenArray.Mod` | Open array parameter (ARRAY OF INTEGER) | |
| `L2_OpenArrayLen.Mod` | LEN() on open array parameter | |
| `L2_StringLiteral.Mod` | String constant as ARRAY OF CHAR | |
| `L2_StringParam.Mod` | String passed to ARRAY OF CHAR param | |
| `L2_StringCompare.Mod` | String/char array comparison | |
| `L2_MultiDimArray.Mod` | ARRAY n, m OF INTEGER | |
| `L2_ArrayOfChar.Mod` | Character-by-character string building | |
| `L2_ArrayBounds.Mod` | Array index bounds checking (ASSERT trap) | |

## Level 3: Records - Done

| Test | Feature | Notes |
|------|---------|-------|
| `L3_SimpleRecord.Mod` | Record type with fields, assign and read | |
| `L3_RecordParam.Mod` | Record as value parameter (read-only, by ref) | |
| `L3_RecordVarParam.Mod` | Record as VAR parameter | |
| `L3_NestedRecord.Mod` | Record containing record field | |
| `L3_RecordArray.Mod` | Record containing array field | |
| `L3_ArrayOfRecord.Mod` | Array of records | |
| `L3_RecordAssign.Mod` | Whole-record assignment (StoreStruct) | |
| `L3_RecordExtension.Mod` | Record type extension (RECORD (Base)) | |
| `L3_TypeTest.Mod` | IS operator for type testing | |
| `L3_TypeGuard.Mod` | Type guard v(ExtendedType).field | |
| `L3_TypeCase.Mod` | CASE statement with type guards | |

## Level 4: Pointers and Dynamic Allocation - Done	

| Test | Feature | Notes |
|------|---------|-------|
| `L4_PointerDecl.Mod` | POINTER TO Record declaration | |
| `L4_New.Mod` | NEW() allocation | |
| `L4_PointerDeref.Mod` | Pointer dereference p^ and field access p.field | |
| `L4_PointerNil.Mod` | NIL comparison, NIL assignment | |
| `L4_PointerParam.Mod` | Pointer as procedure parameter | |
| `L4_PointerAssign.Mod` | Pointer assignment (aliasing) | |
| `L4_LinkedList.Mod` | Linked list: create, traverse, print | |
| `L4_PointerExtension.Mod` | Pointer to extended record, type test with IS | |
| `L4_PointerTypeGuard.Mod` | Type guard through pointer | |

## Level 5: SET Type - Done

| Test | Feature | Notes |
|------|---------|-------|
| `L5_SetLiteral.Mod` | {1, 3, 5}, {}, singleton {x} | |
| `L5_SetRange.Mod` | {2..7} range notation | |
| `L5_SetIn.Mod` | x IN s membership test | |
| `L5_SetUnion.Mod` | s1 + s2 | |
| `L5_SetIntersect.Mod` | s1 * s2 | |
| `L5_SetDifference.Mod` | s1 - s2 | |
| `L5_SetSymDiff.Mod` | s1 / s2 | |
| `L5_SetComplement.Mod` | -s (complement) | |
| `L5_SetCompare.Mod` | =, #, <= (subset), >= (superset) | |
| `L5_SetInclExcl.Mod` | INCL(s, x) and EXCL(s, x) | |
| `L5_SetVariable.Mod` | SET in variables, parameters, records | |

## Level 6: Numeric CASE Statement - Done

| Test | Feature | Notes |
|------|---------|-------|
| `L6_CaseSimple.Mod` | CASE x OF 1: ... \| 2: ... END | |
| `L6_CaseRange.Mod` | CASE with ranges: 3..7: | |
| `L6_CaseElse.Mod` | CASE with ELSE clause | |
| `L6_CaseChar.Mod` | CASE on CHAR values | |
| `L6_CaseNested.Mod` | Nested CASE statements | |

## Level 7: Standard Procedures and Functions - Done

| Test | Feature | Notes |
|------|---------|-------|
| `L7_IncDec.Mod` | INC(x), DEC(x), INC(x, n), DEC(x, n) | |
| `L7_Abs.Mod` | ABS() on positive and negative integers | |
| `L7_Odd.Mod` | ODD() on even and odd values | |
| `L7_Len.Mod` | LEN() on fixed arrays and open arrays | |
| `L7_Assert.Mod` | ASSERT(TRUE) passes, ASSERT(FALSE) traps | |
| `L7_Lsl.Mod` | LSL() logical shift left | |
| `L7_Asr.Mod` | ASR() arithmetic shift right | |
| `L7_Ror.Mod` | ROR() rotate right | |
| `L7_OrdChr.Mod` | ORD() and CHR() round-trip | |
| `L7_Floor.Mod` | FLOOR() real to integer | |
| `L7_Flt.Mod` | FLT() integer to real | |
| `L7_Pack.Mod` | PACK() and UNPK() on reals | |

## Level 8: REAL Arithmetic - Done

| Test | Feature | Notes |
|------|---------|-------|
| `L8_RealConst.Mod` | Real constant declarations | |
| `L8_RealArith.Mod` | +, -, *, / on REAL | |
| `L8_RealCompare.Mod` | Comparisons on REAL values | |
| `L8_RealConvert.Mod` | FLT/FLOOR conversions | |
| `L8_RealParam.Mod` | REAL as procedure parameter | |
| `L8_RealArray.Mod` | ARRAY OF REAL | |

## Level 9: Module System - Done

| Test | Feature | Notes |
|------|---------|-------|
| `L9_Import.Mod` + `L9_ImportLib.Mod` | Basic IMPORT and use of exported proc | |
| `L9_ExportVar.Mod` + `L9_ExportVarLib.Mod` | Exported variable read | |
| `L9_ExportType.Mod` + `L9_ExportTypeLib.Mod` | Exported type used in client | |
| `L9_ImportAlias.Mod` | IMPORT A := ModuleName | |
| `L9_Relocations.Mod` | Module data/code relocation at load time | |

## Level 10: SYSTEM Module (65C816-Specific) - Done

| Test | Feature | Notes |
|------|---------|-------|
| `L10_SystemPutGet.Mod` | PUT and GET to memory addresses | |
| `L10_SystemAdr.Mod` | ADR() returns address of variable | |
| `L10_SystemSize.Mod` | SIZE() returns type size | |
| `L10_SystemVal.Mod` | VAL() type reinterpretation | |
| `L10_SystemBit.Mod` | BIT() test bit at address | |
| `L10_SystemCopy.Mod` | COPY() memory block copy | |
| `L10_SystemTrbTsb.Mod` | TRB/TSB (65C816 test-and-modify) | |
| `L10_Interrupt.Mod` | Interrupt procedure declaration | |

## Level 11: Edge Cases and Stress Tests - Done

| Test | Feature | Notes |
|------|---------|-------|
| `L11_IntOverflow.Mod` | MAX + 1, MIN - 1 behavior | |
| `L11_DeepNesting.Mod` | Deeply nested IF/WHILE (stack pressure) | |
| `L11_ManyParams.Mod` | Procedure with 8+ parameters | |
| `L11_ManyLocals.Mod` | Procedure with many local variables | |
| `L11_LargeArray.Mod` | Large array allocation | |
| `L11_EmptyLoop.Mod` | Zero-iteration FOR/WHILE | |
| `L11_ChainedCalls.Mod` | f(g(h(x))) nested function calls | |
| `L11_ExprPrecedence.Mod` | Operator precedence: 2 + 3 * 4 = 14 | |
| `L11_ShortCircuit.Mod` | (x # 0) & (10 DIV x > 1) doesn't trap | |

## Level 12: Negative Tests (Compiler Error Detection) - Done

Tests that verify the compiler correctly rejects invalid programs.

| Test | Expected Error |
|------|----------------|
| `L12_TypeMismatch.Mod` | Assign CHAR to INTEGER |
| `L12_Undeclared.Mod` | Use of undeclared identifier |
| `L12_DuplicateDecl.Mod` | Duplicate variable name |
| `L12_WrongArgCount.Mod` | Too many/few arguments to procedure |
| `L12_WrongArgType.Mod` | Wrong parameter type |
| `L12_AssignConst.Mod` | Assignment to constant |
| `L12_AssignReadOnly.Mod` | Assignment to read-only value param |
| `L12_MissingSemicolon.Mod` | Missing semicolon |
| `L12_ModuleNameMismatch.Mod` | END name doesn't match MODULE name |

---

## Test Infrastructure

- `run_self_tests.sh` — compiles each test with oc816 and runs it on
  OS16 under em16 -fpga, its output compared with the `.expected`;
  levels can be named (`run_self_tests.sh L4 L9`)
- `make test` (in `self/s816`) — the whole suite
- The suite came from 65Tools' `oc/test` (as of 65Tools 275e1d0), where
  it was first written for the C compiler, now in 65Tools' history only

## Implementation Order

The levels are ordered by dependency and suggested implementation priority:

1. **Level 1** — Solidify foundations, fill any gaps
2. **Level 2** — Arrays mostly working, add open array and bounds checking
3. **Level 3** — Records need work (extension, type tests, StoreStruct)
4. **Level 4** — Pointers and NEW (significant compiler work)
5. **Level 5** — Complete SET operations
6. **Level 6** — Numeric CASE statement
7. **Level 7** — Standard library completeness
8. **Level 8** — REAL type (major feature, needs floating-point emulation)
9. **Level 9** — Module system and relocations
10. **Level 10** — SYSTEM module completeness
11. **Level 11/12** — Hardening and error detection
