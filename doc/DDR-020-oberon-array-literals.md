# Design Decision Record 020: Array Literals (Aggregate Construction)

**Author:** Jason Swain
**Date:** 2026-08-04
**Status:** **Accepted.** Syntax and scope settled; §4 (element-type elision) resolved to **Option A — require the element-type prefix** (2026-08-04). The `{}` bracket carries the whole aggregate family; `[]` is deliberately left unused (reserved for generics).
**Relationship to prior records:** Sibling to **DDR-019** (record literals). It generalises the existing `ARRAY OF BYTE {…}` const-array literal to record/nested elements and to runtime construction, and reuses DDR-019's target-directed `RecordLitInto` machinery. Together they form the `{}` aggregate-literal family.

---

## 1. Context

We already have a const-array literal — `ARRAY OF BYTE {10, 20, 30}` — but it is `CONST`-only, scalar-element-only, and lives in the data section. Two things are missing to make arrays as writable as records now are: **record (and nested) element types**, and **runtime construction** (`arr := ARRAY OF Point {…}` with runtime element values). This record adds both, staying inside the syntax and machinery already built.

Two framing decisions taken with the author (discussion, 2026-08):

- **Stay in the `{}` family; do *not* add a `[…]` literal.** `ARRAY OF T {…}` for the literal echoes `ARRAY OF T` for the type, generalises the existing form (no migration of `L14`), and — decisively — **reserves `[]` for a future type-parameter / generics syntax** (`List[T]`, `Map[K,V]`; the parent OO record's §3 typed-collections item). Spending `[]` on array literals now would foreclose the feature most likely to want it. See DDR-019's sibling discussion.
- **This is the array analogue of DDR-019, not a new mechanism.** Detection, offsets, zero-fill, and the target-directed fill are the same.

## 2. Syntax

An array literal is a **type prefix + `{ positional elements }`**:

```
  ARRAY OF Point { Point{x:=1; y:=2}, Point{x:=3; y:=4} }   (* anonymous array type *)
  BYTE { 10, 20, 30 }                                        (* migrated const-array form *)
  Vec { 1, 2, 3 }                                            (* named array type: TYPE Vec = ARRAY 3 OF INTEGER *)
```

This makes the whole aggregate family one rule — **`TypeName{…}` is "an aggregate of TypeName," parsed by the type's form**:

| Literal | Meaning |
|---|---|
| `{ a, b, c }` | **set** (no type prefix) |
| `Point{ x := 2; y := 3 }` | **record** (type is a record → named fields, `:=`) |
| `ARRAY OF Point { e0, e1 }` | **array** (type is an array → positional elements) |
| `Vec{ e0, e1, e2 }` | **array** via a named array type |

The parser resolves the leading qualident to a type and branches on `form` (Record → named fields; Array → positional elements); a leading `{` with no type is a set. All one-token detection, no lookahead, `[]` untouched. Migrate the current `ARRAY OF BYTE {…}` scalar-const form onto this same path (element types simply widen from "1–2 byte scalar" to "any element type").

## 3. Scope

- **Element types:** scalars (as today), **records** (each element a record literal, or a record-valued expression), and **nested arrays** (each element itself an array literal). Uniform with DDR-019's nested records.
- **Runtime form (both a `CONST` and a runtime value):** in an assignment `arr := ARRAY OF T {…}`, fill the target `arr` in place — zero it (strict zero-fill, §5.1 of DDR-019 semantics), then for each element `arr[k] := e_k`. Because the indices are the compile-time constants `0, 1, 2, …`, every element target is a **constant-index `Var`** — which `RecordLitInto`/`Store` already handle, so this *sidesteps the `RegI` gap* entirely (DDR-019 §9). `CONST` arrays still lower to the data-section image.
- **Length:** the element count sets the length of an anonymous array type (as the current const form does); against a fixed-length target, fewer elements than the length **zero-fill the tail** (consistent with record partial init), and more than the length is an error.

## 4. Decision — element-type elision (the one open fork)

Inside `ARRAY OF Point {…}` the element type is known, so an element could drop its prefix: `ARRAY OF Point { {x:=1; y:=2}, {x:=3; y:=4} }`.

- **Option A — require the element-type prefix** *(recommended)*. One rule for the whole family (matches DDR-019's "prefix required", §3.3). No ambiguity, maximally explicit, Wirthian. Cost: repetition of the element type.
- **Option B — allow elision for *record* element types only.** Unambiguous for records because a record literal contains `:=`, which a set cannot, so `{x:=1; y:=2}` can't be misread as a set. **Not** offered for array-typed elements, where a bare `{1, 2}` element genuinely collides with set syntax.

**Extension is not a hazard either way.** A value-record array is monomorphic — every slot is exactly the element type, since a value record cannot hold an extension in a base-typed slot (polymorphism is via pointer arrays, whose elements can't be `{…}` literals). So an elided `{…}` binds unambiguously to the element type, and naming an extension's field in it errors cleanly ("unknown field") rather than mis-binding. Elision is therefore *safe*; it simply recovers no type information you didn't already have — pure keystroke-saving, which is why it reads as an un-Oberon convenience.

**Decision (2026-08-04): Option A — require the element-type prefix.** Elision's safety is real but its benefit is only brevity, and "optional but attractive" tends to become habitual, eroding the one-rule clarity for no type-safety gain. One rule holds for the whole aggregate family (record and array literals both name their type).

## 5. Implementation sketch

Reuses DDR-019 almost entirely:
- **Parser:** the existing `ARRAY OF T {…}` / qualident-`{` detection widens to record/array element types; against a runtime target it calls a target-directed `ArrayLitInto(target, elemType, count)` that zeroes `target` then fills `target[k] := e_k` (each a constant-index `Var`, via `Field`/`Index` + `Store`, or `RecordLitInto` when the element is a record literal).
- **CONST:** unchanged data-section path, elements placed by `k * elemSize` (records/nested via `CopyStr`, already present).
- **`RegI` array *targets*** (`m[i] := ARRAY OF … {…}`, variable `i`) inherit DDR-019's deferral — but *element* targets inside a literal are always constant-index, so the literal itself needs no held-address machinery.
- **LLVM:** rejects cleanly, same as the record/const-array literals (no data section).

## 6. Consequences

1. Arrays become writable as values — tables, fixed vectors, message bodies — in a `CONST` and at runtime, on the 816, reusing the record-literal machinery.
2. The aggregate family is closed and uniform: `{}` set, `T{}` record/array by form; **`[]` stays free for generics.**
3. `L14` (`ARRAY OF BYTE {…}`) keeps working — it becomes a special case of the generalised form, not a separate feature.
4. No new bracket, no type-grammar change (`ARRAY OF T` remains the type syntax — DDR-019 sibling discussion, and the SET/RECORD type-vs-literal precedent).

## 7. Amendments this record proposes to prior records

- **DDR-019 →** the `{}` aggregate family now includes arrays; the "prefix required" decision (DDR-019 §3.3) extends to array-element prefixes if §4 Option A is taken.
- **The array-literal `[…]` idea (raised in the DDR-019 discussion) → withdrawn**; `[]` is reserved for future type parameters.
- **No change** to the `ARRAY OF T` *type* syntax.
