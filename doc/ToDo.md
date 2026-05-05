x ARC
x Records on the stack with pointer fields don't release those fields on scope exit. Stack records are rare in idiomatic Oberon; document and add a TD-driven cleanup helper later.
x Record-to-record assignment via ORG_StoreStruct is still raw memcpy — pointer fields aren't retain/release-balanced. Would need oc_assign_record(dst, src, td) runtime helper.
x Cycles leak silently. WEAK POINTER syntax + weak-ref table is the next item if you want to plug that.
/ Memory usage SYSTEM proc
/ C library interface

x Sets finish (INCL/EXCL/range expressions in set construction).
x REAL end-to-end verification — operations are wired but never linked into a runnable test.
x Type guards end-to-end (WITH p: T DO ... END, type-CASE).
x Recursive auto-compile of imports — so oc -o prog Main.Mod automatically rebuilds stale imports.
x Driver polish: -c to skip the link, -S to emit only .ll, etc. include runtime.o automatically

x Rutime module loading

# Runtime

## Base
x SYSTEM
x Modules
- FileDir
- Files


- CLAUDE.md


## Window 
Automatically sizes to the full terminal.
Manages contained panes.

## Pane
Sub-region of Window. Can be sized. Non-overlapping.

# Design By Contract

PROCEDURE Test(a: INTEGER, p: POINTER) 
VAR
  i: INTEGER;
REQUIRE
  a > 0;
  p == NIL;
BEGIN
  p := NEW(typ);
  RETURN p;
ENSURE
  p <> NIL;
END

# Single value functions

PROCEDURE Result(b: BOOLEAN)

TestRunner.Result := a > 10;

