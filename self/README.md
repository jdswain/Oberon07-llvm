# Self-hosted Oberon compiler

The compiler in extended Oberon (all DDR features), with one **shared
frontend** driving two **backends**.

```
self/
  ORS.Mod  ORB.Mod  ORP.Mod          # shared frontend (scanner, symtab, parser/driver)
  llvm/    ORG.Mod  ORG_rt.c  main.c  gen_bridge.py  Makefile   # LLVM backend  -> oc-self
  s816/    ORG.Mod  OCG.Mod  main.c  Makefile                   # 65C816 backend -> oc816
```

The frontend is target-independent: it reads and writes only
`Item.mode/type/a/b/rdo`, which each backend's `ORG.Mod` defines with its own
private internals. Wirth's architecture is preserved — each backend owns its
code generator; the frontend never sees target details.

## Building

Each backend directory **copies** the shared `.Mod` files in before compiling,
so per-target artifacts (`.smb`/`.o`/`.ll`/`.816` — type sizes differ by
target) never collide. Stage-0 for both is `../bin/oc` (the C LLVM compiler).

```
cd llvm && make      # -> oc-self  (LLVM backend; needs llvm-config)
cd s816 && make      # -> oc816    (65C816 backend; pure Oberon, no libLLVM)
```

## Backends

| | LLVM (`oc-self`) | 65C816 (`oc816`) |
|---|---|---|
| WordSize / INTEGER | 4 | 2 |
| Pointer | 4 | 4 (addr + bank) |
| Interface (`IntfcSize`) | 16 | 8 |
| Memory management | ARC | GC (mark/sweep, later stage) |
| Output | `.ll` / `.o` | self-contained relocatable `.816` |

`oc816 Module.Mod [-s] [-m] [-x | -816] [-O0] [-I dir]`: `-s` allows a new
symbol file, `-m` writes `Module.map` (each procedure's code offset), and
`-x` makes code for Verilog65C816's core with its extension after WDM
(its `docs/65C832.md`; `OCG.xops`):

- an INTEGER `*` by UML;
- `DIV` and `MOD` by DIV, which rounds down as Oberon's do;
- a LONGINT `*` by three UMLs, a REAL `*` by four (the mantissas' halves)
  and its exponents' shifts by LSR #7;
- a LONGINT `DIV` and `MOD` by one DIV when both are 16-bit numbers, else
  by UDV in parts, a divisor of 10000H or more still a bit a step;
- a multiply, `DIV` or shift by a constant power of 2 by ASL, LSR or ASR
  #n, and an index by its element's size by ASL #n or UML.

That code runs only on such a core (em16 -fpga). Without `-x` the code is
as it was, byte for byte. OS16 is compiled with `-x`.

By default the code is for the board's core with its banked direct page
and stack (`WDM #$B1`, Verilog65C816's `docs/BankedDP.md`), as OS16 runs
it: D's high byte is the bank of both. `-816` (`OCG.stock`) makes code for
a stock 65C816, both in bank 0 and D any address there: a local's address
has bank 0 (`ORGI.stackBank`), and a local beyond `d,S`'s 255 bytes is
reached at `S + v - D` (`OCG.bigX`). It excludes `-x`; a stock 65C816 has
no extension.

The code generator's registers are words of the direct page, so a value
goes through one: `LDA x`, `STA r`, then `LDA r` for what is done with it.
`OCG`'s peephole holds a store to a register back, with the instructions
after it, and leaves out an `LDA r` while A is still r's value, and the
held store when r is stored again before anything reads it or the code
generator frees r (`OCG.Dead`: a statement's end, a condition's branch).
It never reorders, and leaves alone the bytes up to a branch whose place
was counted ahead (`Here() + n`). `-O0` (`OCG.peep`) turns it off. With
it, and a signed INTEGER compare by its sign bit, a byte read as a word,
a small frame by `PHA`/`PLY` and a NIL test of the word in A, OS16's code
is 9% smaller and runs 7-14% fewer cycles.

The 816 loads every module into one bank; dynamic-dispatch vtables and
interface itables use loader-filled absolute in-bank addresses. Type
descriptors are generated deferred (offsets assigned in `ORG.FinalizeTDs`,
called before the `.smb` is written so cross-module type tests / NEW /
interfaces read real offsets).

## Verification

- **LLVM:** `oc-self` output must stay byte-identical to `bin/oc` — compile a
  module with each and `diff` the `.ll`.
- **816:** `cd ../../65/65Tools/oc && make test_self` runs the em16 golden
  suite (all levels + L16 OO + L17 interfaces). Override the compiler with
  `OC=/path/to/oc816`, and with `OCFLAGS=-x` for the extension's code
  (L18_ArithSums checks its arithmetic). The C compiler in that repo
  stays as a reference cross-check; see its `CLAUDE.md`.

Design records live in `../doc/DDR-*.md` (interfaces: DDR-008; the ABI
resolution for both backends is DDR-008 §6).
