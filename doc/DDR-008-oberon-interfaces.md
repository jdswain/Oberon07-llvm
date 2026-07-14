# Design Decision Record 008: Interfaces for Oberon-07

**Author:** Jason Swain
**Date:** 2026-07-14
**Status:** Accepted (semantic design); one sub-decision deferred (runtime representation, §6)
**Relationship to prior record:** This document extends *Design Decision Record: Object-Oriented Extensions to Oberon-07* (DDRs 001–007). It resolves the "Interfaces" open item in that record's §3 and is intended to slot into its §5 sequencing at step 4. The parent document is **not** modified; §8 below states the amendments it would receive.

---

## 1. Context

The parent record established (DDR-001) type-bound procedures with single record extension, and identified interfaces — not the class machinery — as the genuinely missing polymorphism feature, because single extension yields only a rigid inheritance tree whereas most real reuse needs "any type that can do X." The parent left the mechanism open, specifically the structural-vs-nominal fork. This record settles that fork and specifies the feature.

Three constraints were given as design inputs:
1. An interface is defined in a manner similar to a `RECORD`.
2. Interfaces may include other interfaces simply by naming them.
3. A `RECORD` implements interfaces by *declaring* conformance; the compiler checks conformance, so no runtime check is required.

---

## 2. Decision — Nominal, declared-conformance interfaces

### DDR-008 — Interfaces
**Status:** Accepted

Adopt **nominal** interfaces: a record conforms to an interface only when it explicitly declares that it does, and the compiler verifies the declaration. This is the more Oberon-ish choice — it says what it means, and conformance failure can be reported precisely at the record's own declaration. It also keeps separate compilation clean (§5). Its one significant cost is recorded and accepted in §7.

The remainder of this section specifies definition, inclusion, and conformance; §3–§7 record semantics, the checking model, the deferred representation choice, and consequences.

---

## 3. Interface definition

An interface is defined like a `RECORD`, but its members are **method signatures only** — no fields, no bodies. The receiver is implicit (it is whatever type conforms).

```
TYPE
  Reader = INTERFACE
    PROCEDURE Read(VAR buf: ARRAY OF BYTE): INTEGER
  END;

  ReadWriter = INTERFACE
    Reader;                    (* inclusion by naming — see §4 *)
    PROCEDURE Write(buf: ARRAY OF BYTE): INTEGER;
    PROCEDURE Close()
  END;
```

---

## 4. Inclusion by naming (constraint 2)

A bare interface name in the member position **includes** that interface. The semantics are **flattening**: the including interface's method set is the union of the named interface's methods and its own. Above, `ReadWriter`'s method set is `{Read, Write, Close}`.

**Why this is safe when multiple record inheritance is not.** An interface carries no state and no implementation, so inclusion has neither the state-diamond nor the implementation-diamond problem. If `A` includes `C`, `B` includes `C`, and `D` includes both `A` and `B`, `C`'s methods simply appear once; identical signatures collapse. The **only** failure mode is two included interfaces declaring the same method *name* with *different* signatures — a clean compile-time ambiguity error. This yields genuine multiple inheritance **of type** with none of the hazards, precisely because the only thing inherited is obligations.

---

## 5. Conformance declaration and checking (constraint 3)

### 5.1 Syntax — a slot distinct from extension
Record extension already owns the parenthesised `(Base)` form and permits exactly one base. Conformance is a *different* relationship and permits *many* interfaces, so it is given its own keyword rather than overloading the parentheses (consistent with the keywords-over-sigils recommendation in the parent's DDR-007):

```
File = RECORD (Base) IMPLEMENTS Reader, Writer
  ...fields...
END
```

This composes single extension with multiple conformance in the Java manner: **one base record, many interfaces** — which is exactly how the design escapes the rigid single-extension tree.

### 5.2 The check
For every method in each named interface's **flattened** set (§4), the record must have a matching type-bound procedure (name + signature). Any gap is a compile error that names the missing method exactly.

### 5.3 Inherited conformance
Conformance is inherited: if `Base IMPLEMENTS Reader`, any extension of `Base` still conforms without re-declaring (its overrides preserve signatures under the parent's DDR-002), and may declare additional conformances of its own.

### 5.4 No runtime check — and the symmetry
Because conformance is declared and checked where the record is defined, the compiler has both the record's methods and the interface definition in hand, and builds the method table for that (record, interface) pair at compile time.

- **Upcast** (record → interface variable) is statically known safe: no check.
- **Dispatch** through an interface is an indexed indirect call: no check.
- **Narrowing** (interface → concrete type, or interface → sub-interface) is *not* statically known and **does** require a runtime test — but this introduces **no new machinery**. The record still carries its DDR-001 type tag, so `v IS File` and the guard `v(File)` work on an interface reference unchanged. This is the guard direction from the parent's DDR-006 reappearing for narrowing; it is the honest symmetry to the "no check needed" claim, which holds strictly for the upcast/dispatch direction.

---

## 6. Deferred sub-decision — runtime representation (ABI)

**Status:** Deferred; not blocking; may differ per backend.

How an interface reference is represented at runtime is left open, because it is pure ABI — invisible in source, **not** signature-shaping, and therefore safe to decide after libraries exist. The two classic options:

- **Fat pointer** (data pointer + method-table pointer; Go's model): dispatch is a cheap in-hand index, but every interface reference is two words.
- **Plain pointer** (data pointer only): one-word reference, but dispatch must go data → type descriptor → locate this interface's table, a lookup per call.

Guidance:
- **LLVM backend:** fat pointers are trivially cheap; use them.
- **65C816 backend:** genuine tension — two-word references cost scarce memory and zero-page pressure, while the per-call lookup costs scarce cycles. Decide on measurement.

Because this is ABI only, **the two backends need not agree**, and no library source changes when the choice is flipped.

---

## 7. Consequences

1. **Interface references are reference types.** An interface value points at a heap record with a dynamic type, consistent with DDR-001's "polymorphism arrives through pointers." A value type (e.g. `INTEGER`) therefore still cannot sit behind an interface without a wrapper record — the boxing point from the parent's generics discussion (§3, generics) survives unchanged.

2. **No free universal type.** Under nominal conformance, an `Any = INTERFACE END` is implemented only by records that explicitly declare it, not by everything — nothing conforms implicitly. Any "any-reference" must be designed deliberately; there is no Go-style empty-interface-for-free.

3. **Nominal conformance forecloses retroactive conformance — the accepted cost.** If a foreign library record has exactly the right methods but does not declare `IMPLEMENTS YourInterface`, it cannot be used through that interface: its declaration is not yours to change, and keeping conformance at the record's own site (which is what keeps separate compilation clean, §5.4) means no third party can assert conformance on its behalf. Structural interfaces exist largely to solve this interop problem; choosing nominal gives it up.
   - **Standard workaround:** an *adapter* record that wraps the foreign type, declares the conformance, and forwards each method — cheap, explicit, one allocation.
   - **Open question worth settling before modules depend on library boundaries:** whether the adapter is acceptable for the intended library ecosystem, or whether a narrow escape hatch (an *external* conformance assertion) is wanted. Painless to decide now; painful to retrofit later.

---

## 8. Amendments this record makes to the parent DDR

For traceability, were the parent document to be revised it would receive:

- **§3 "Interfaces (structural, Go-style)" open item →** resolved: **nominal, declared-conformance** interfaces as specified here (DDR-008, Accepted). The parenthetical "(structural, Go-style)" is superseded.
- **§3 add** a pointer noting the retroactive-conformance cost (§7.3 here) and the adapter/escape-hatch question as the residual open item.
- **§5 Sequencing step 4** ("Interfaces — resolve structural vs nominal and implement") → the structural-vs-nominal question is now closed; step 4 becomes implementation of this record, with the runtime-representation sub-decision (§6 here) tracked as a deferred, non-blocking ABI item that may be settled per backend after libraries.
- **No change** to DDRs 001–007 themselves; this record depends on DDR-001 (type tags, pointer-receiver dispatch), DDR-002 (signature-preserving overrides), DDR-006 (the guard/narrowing direction), and DDR-007 (keywords over sigils, applied to `IMPLEMENTS`).
