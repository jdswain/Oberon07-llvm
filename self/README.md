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
  `OC=/path/to/oc816`. The C compiler in that repo stays as a reference
  cross-check; see its `CLAUDE.md`.

Design records live in `../doc/DDR-*.md` (interfaces: DDR-008; the ABI
resolution for both backends is DDR-008 §6).
