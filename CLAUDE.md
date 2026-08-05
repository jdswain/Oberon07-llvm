This is an LLVM-based Oberon compiler.

It is based on Wirth's Oberon-07 compiler; that code was ported to C for a
standalone compiler and then reused here on the LLVM port.

The LLVM port uses LLVM automatic reference counting instead of garbage
collection.

## Two backends, one shared frontend

`self/` holds the self-hosted compiler in extended Oberon (all DDR features:
methods, constructors, SUPER, interfaces, WEAK):

- `self/{ORS,ORB,ORP}.Mod` — the shared frontend (scanner, symbol table,
  parser/driver). It is target-independent; it touches only
  `Item.mode/type/a/b/rdo`, which both backends define.
- `self/llvm/` — the LLVM backend (`ORG.Mod` + C bridge), builds `oc-self`.
- `self/s816/` — the 65C816 backend (pure Oberon: `OCG.Mod` encoder +
  `ORG.Mod` codegen + `main.c` driver), builds `oc816`. It targets the 65C816
  and emits self-contained relocatable `.816` modules.

Each backend dir copies the shared `.Mod` files in before compiling, so its
`.smb`/`.o`/`.ll`/`.816` artifacts stay local (type sizes differ per target).
Stage-0 for both is `bin/oc` (the C LLVM compiler built from `src/`).

Key backend differences: the **816 uses GC, not ARC** (a Wirth-style
mark/sweep collector is a later stage; the backend already emits the GC
contract surfaces — pointer maps, module tables, tag headers — and WEAK is a
semantic no-op that still excludes fields from pointer maps). The 816 is
`WordSize=2`, pointers 4 bytes (addr+bank), and all modules load into one
bank. Dynamic dispatch and interface itables use loader-filled absolute
in-bank addresses.

## Verification

- LLVM: `oc-self` output must stay byte-identical to `bin/oc` (diff `.ll`).
- 816: `cd ../65/65Tools/oc && make test_self` (or
  `OC=… ./test/run_self_tests.sh`) runs the em16 golden suite across all levels
  plus OO (L16) and interface (L17) goldens. The C compiler there (`bin/oc`,
  `run_level*_tests.sh`) is kept as a cross-check reference for now.
