# Design Decision Record 013: Object-Oriented Realization (As-Built)

**Author:** Jason Swain
**Date:** 2026-07-28
**Status:** Accepted (as-built record). Documents what was *implemented* on both backends against the designs in the parent OO record and DDRs 001–008; it is descriptive, not a fresh proposal. Residual open items (§6) are the only decisions still live.
**Relationship to prior records:** Realizes the parent *Object-Oriented Extensions to Oberon-07* (DDRs 001–007) and **DDR-008** (interfaces). It changes none of their *decisions*; it records the concrete language surface and the two-backend ABI that now exist, and flags where the implementation added a constraint the design did not anticipate. Where a later networking/concurrency record says "the OO mechanisms we have," this is the referent.

---

## 1. Context

The OO design was settled on paper (DDRs 001–008) *before* any library modules were written, deliberately. It is now implemented and self-hosting on both backends — the LLVM code generator and the 65C816 native generator — with a green test suite covering methods, override, dynamic dispatch, constructors, SUPER, and interfaces (levels 16–17 of the em16 golden suite; `tests/Methods|Ctors|Super|Ifaces` on LLVM). This record captures the realized surface and ABI so that library and networking work can build on a stable, written contract rather than on the code.

## 2. Realized language surface

All of the following are implemented, parsed via the keywords `WEAK INIT OVERRIDE SUPER INTERFACE IMPLEMENTS` (ORS), and exercised by the test suite.

- **Type-bound procedures (methods)** — `PROCEDURE (r: T) M(...)`, single receiver, pointer or VAR-record. Single record extension only (DDR-001). Dispatch is dynamic through a per-type vtable; slots are stable across extension (an override keeps its parent's slot).
- **`OVERRIDE`** — an override must name `OVERRIDE`; a method that shadows without it, or `OVERRIDE`s nothing, is a compile error. Signatures must match.
- **Constructors** — `INIT` bodies; `T.Name(args)` allocates and initialises in one step; NEW-policy and chaining enforced by the frontend; `SUPER.Init(...)` chains to the base.
- **`SUPER`** — statically-dispatched call to the parent's implementation of a method (used for chaining and augmentation).
- **Interfaces (DDR-008)** — nominal, declared conformance: `RECORD IMPLEMENTS I`. Definition is method-signatures-only; inclusion by naming (flattening union). Conformance is checked entirely at compile time. Interface values are reference values (fat pointers, §3).
- **`WEAK`** — a reference qualifier meaningful to ARC (LLVM) and a semantic no-op on the 816; on both it excludes the field from the GC/ARC pointer map (§4).

## 3. Realized ABI — interfaces and dispatch

Two decisions from DDR-008 §6 were resolved during implementation and are now fixed:

- **Vtable dispatch.** Each record type descriptor (TD) carries `[size][3 ancestors][nofmeth][vtable slots…][ptr-map]`. Dynamic dispatch is `receiver → tag(=[obj−hdr]) → vtable[slot]`. Slots hold the method's address; the mechanism for *producing* that address differs per backend (§4).
- **Interfaces are fat pointers `{data, itable}`.** `data` is the object pointer; `itable` points at a per-`(record, interface)` constant table of **vtable slot indices** — not function pointers. Dispatch is `data → tag → vtable[ itable[k] ]`: two indexed loads, no search. Because slot indices are position-independent, one itable serves every extension and every module, and `pointer → interface` conversion is a compile-time constant. Sizes: `IntfcSize = 16` on LLVM (two native pointers), `8` on the 816 (addr+bank ×2). The full rationale is DDR-008 §6 (resolution note).

## 4. Realized ABI — the two backends

| | LLVM (`oc-self`) | 65C816 (`oc816`) |
|---|---|---|
| Memory management | ARC (retain/release; `WEAK` = non-retained) | GC, mark/sweep — *deferred stage*; backend emits pointer maps + tag headers now, `WEAK` excludes fields from them |
| Method return convention | native call/ret | **far/RTL** for *every* method (dynamic dispatch is always a long call; the vtable demands one uniform convention across overrides) |
| Vtable slot contents | function pointer (linker-resolved) | **absolute in-bank address, loader-filled** (all modules load into one bank; no per-caller code base) |
| itable slot contents | `i32` vtable index (internal global) | 2-byte vtable index in the module data section; `itable := static_base + offset` at conversion time |
| Type descriptors | emitted inline | **deferred** — offsets assigned in `FinalizeTDs` *before* `.smb` export, so cross-module type tests / NEW read real offsets |
| `IntfcSize` | 16 | 8 |

The 816 choices (loader-filled absolute vtable/itable addresses, deferred TDs, far/RTL methods) are what make cross-module OO and interfaces work when modules are relocatable and load into a single bank. They are recorded in the 816 backend notes and DDR-008 §6.

## 5. Consequences

1. Library code may rely on **methods, override, constructors, SUPER, and interfaces** as a stable, identical *source-level* surface on both backends; only the ABI differs and it is invisible to source.
2. Interface dispatch costs two indexed loads on both backends — cheap enough to use freely as the *input-polymorphism* seam the parent record intended (strategy/callback/visitor, `Reader`/`Writer`/`Conn`).
3. The 816's uniform far/RTL method convention means a method is never a near/RTS procedure — a minor code-size cost accepted for a single dispatch convention.
4. `WEAK` gives a break-cycles tool for ARC and a pointer-map exclusion for the future 816 GC without source divergence.

## 6. Residual open items

These are the only OO decisions still live; none block networking, but several touch library-boundary design and are cheap to settle now, painful later.

- **Retroactive conformance (DDR-008 §7.3).** Nominal conformance means a foreign record with the right methods but no `IMPLEMENTS` cannot be used through an interface. *Options:* (a) adapter-record workaround only (status quo); (b) a narrow *external* conformance assertion (`ASSERT IMPLEMENTS`-style) at the using site. **Recommendation:** (a) until a real cross-library case appears; revisit before publishing library boundaries.
- **Interface method-call on a non-addressable temporary (816 only).** `MakeShape(...).Area()` — a method call directly on an interface-typed *function result* — is rejected on the 816 (the fat value must be addressable so the receiver and itable can be re-read at call time). *Options:* (a) keep the restriction, require binding to a variable first (status quo, documented); (b) spill interface temporaries to a hidden local automatically. **Recommendation:** (a); (b) is a small codegen addition if it becomes a nuisance.
- **Abstract methods / interfaces without a default.** Not currently expressible beyond "interface = all-abstract." *Options:* (a) none (interfaces cover the abstract case); (b) an `ABSTRACT` method marker on records. **Recommendation:** (a).
- **Closures and an iteration protocol (parent §3).** Still open, and *decisive for library shape*: an `each`/`map` internal-iteration protocol needs a callback type in the signature. **Recommendation:** decide when the collection library is designed, not before — but note it here because networking callbacks (§DDR-014/015) may want it first.
- **Typed collections / narrow generics (parent §3).** Still open; unaffected by this record.

## 7. Amendments this record makes to prior records

- **DDR-008 §6 →** the resolution note (fat pointers, slot-index itables, per-backend sizes) is now *implemented*, not merely resolved; this record is the as-built cross-reference.
- **Parent §3 "Interfaces" residual (§7.3 retroactive conformance) →** carried forward unchanged as an open item (§6 here).
- **No change** to any accepted decision in DDRs 001–012.
