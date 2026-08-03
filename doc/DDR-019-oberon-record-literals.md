# Design Decision Record 019: Record Literals (Named-Field Aggregate Construction)

**Author:** Jason Swain
**Date:** 2026-08-03
**Status:** **Accepted; implemented 2026-08-03** (816; LLVM cleanly rejects). All five §8 decisions ratified (general expression; `:=`; `;`; type prefix required; zero-fill). Implemented: constant-valued literals as a factor value (`CONST` + expression position), and **runtime-valued** literals target-directed on the RHS of an assignment to a `Var`/`Par` record (zero via `StoreStruct` from a zeroed image, then `Field`+`Store` per field, nested-recursive). Named/out-of-order/partial/nested/reassignment all correct (goldens `L3_RecordLit`, `RORun`). Still deferred: `RegI` targets (`arr[i]`, `p^` — need an `ORG`-internal held-address fill), same-module `CONST` records (Oberon-07 `CONST`-before-`TYPE` ordering), and LLVM support. See §9.
**Relationship to prior records:** Sibling to the **array-literal** extension already implemented (`ARRAY OF BYTE {…}` / `ARRAY OF INTEGER {…}`, const-only, stored in the module data section — 816 today; §5). Evolves the C 816 compiler's *positional* record constant (`RECORD (TypeName) { v1, v2 }`) into a **named-field** form. Interacts with DDR-013 (OO: constructors are the *pointer/heap* construction path; this record is the *value*-record path — §4.4).

---

## 1. Context

Oberon can declare a record type but has no way to *write a record value* — you must declare a variable and assign each field on its own line. That is verbose for configuration/data aggregates and impossible in a `CONST`. The array-literal extension already added `{…}` aggregate syntax for arrays; this record does the same for records, but **by field name rather than position**, because record fields are named (and reordering a record's declaration must not silently repoint a literal). Go and Swift both offer this; the goal is the same capability with a **distinctly Oberon** surface.

Guiding constraints (from the brief): named fields; able to construct nested/child records inline; looks Oberon (so *not* `BEGIN/END` — that reads as a statement block; `{…}` matches the array literal); implementation expected to be small.

## 2. Scope — const-only or general expression?

- **Option S1 — `CONST` only.** A record literal is a compile-time constant, like the array literal: all fields are constant expressions, emitted into the module data section, bound to a `CONST` name. Cheapest; matches the array feature exactly.
- **Option S2 — general expression *(recommended)*.** A record literal is an expression usable anywhere a record value is expected — `v := Point{…}`, a value argument, a `RETURN`. Fields may be *runtime* values. Subsumes S1 (a literal with all-constant fields in a `CONST` uses the const path). This is the Go/Swift capability and what "construct records as part of the syntax" implies.

**Recommendation: S2.** It is the more useful feature and, notably, the general (runtime) form is **more portable than the array literal**: it lowers to ordinary field stores (evaluate each field, store at its offset), which both backends already do — so runtime record literals work on **LLVM and 816 alike**, unlike the const-array which needs a data section (816-only today). Only the `CONST`-record case needs the data-section/struct-constant path (816 now; LLVM could add it via struct globals later, §5).

### 2.1 Rejected alternative — "just use constructors / factory procedures"

The pure Oberon-07 idiom for building a record is a **factory procedure** (`PROCEDURE MakePoint(x, y: INTEGER): Point`), and this project additionally has **OO constructors** (DDR-013 `T.Init`). Neither subsumes the record literal, and the literal does not subsume them — they are complementary:

- A procedure (factory *or* constructor) **cannot be a compile-time constant.** `CONST Origin = Point{x := 0; y := 0}` is expressible *only* as a literal. This alone clears the "capability, not sugar" bar.
- A factory is **positional** (reintroducing exactly the ordering fragility named fields remove) and needs **one procedure per record type** (boilerplate the literal eliminates). Partial/optional construction (`Config{verbose := TRUE}` + zero-fill) would need overloading or default parameters, which Oberon lacks; the literal gets it from field naming.
- Conversely the literal does **not** replace constructors: construction that runs *logic*, maintains invariants, chains to a base (`SUPER`), or allocates on the **heap** is the constructor's job (DDR-013, §4.4/§4.5).

**Division of labour:** *record literal* = declarative value aggregate, and the only route to a constant record; *constructor* = construction with behaviour / heap / inheritance; *factory procedure* = the no-language-feature fallback for runtime value construction when neither is warranted.

**Honesty on cost.** This extension **grows the grammar** by one expression form — it does *not* simplify the language. It simplifies *programs* (removes factory-proc boilerplate, kills the positional-ordering hazard) and adds a capability nothing else provides (constant records). It is Wirthian only in its *economy* — no new operator or keyword, reusing `:=` and the existing `{}` aggregate family — not in reducing language size.

## 3. Syntax (the review item)

### 3.1 Recommended form

```
TypeName { field := expr ; field := expr ; … }
```

- **Delimiters `{ }`** — matches the array literal; `BEGIN/END` rejected (reads as a statement block, not a value).
- **Binding `:=`** — Oberon's assignment operator; a field binding reads exactly like the assignment it replaces. (`:` is Go/Swift but collides with type ascription; `=` reads as comparison/const.)
- **Separator `;`** — matches record *field declarations* (`RECORD x: INTEGER; y: INTEGER END`) and makes the body read as a short statement sequence, which `:=` reinforces.
- **Type prefix required** — explicit, Oberon-ish, and it is what disambiguates a record literal (`TypeName{…}`) from a set literal (`{…}`) for the parser (§6).

Examples:

```
p   := Point{x := 3; y := 4};
seg := Line{ a := Point{x := 0; y := 0};        (* nested child record *)
             b := Point{x := 10; y := 4} };
CONST Origin = Point{x := 0; y := 0};           (* also a constant *)
Draw(Rect{w := 640; h := 480})                  (* as a value argument *)
```

### 3.2 Alternatives to weigh

| Axis | Recommended | Alternatives |
|---|---|---|
| Delimiters | `{ }` | `BEGIN … END` (rejected — statement-block feel) |
| Field binding | `field := expr` | `field: expr` (Go/Swift; clashes with type ascription) · `field = expr` (reads as comparison) |
| Separator | `;` | `,` (matches the array literal's comma list, but `,`-separated `:=` assignments read oddly) |
| Type prefix | required (`TypeName{…}`) | elided where the target type is known (`v := {x := 3; y := 4}`) — optional sugar, §3.3 |

The tension to settle: `;` echoes record *declarations* and the statement-like `:=`; `,` echoes the *array literal*. Picking `;` makes record literals consistent with record decls; picking `,` makes both aggregate literals use the same separator. Recommendation leans `;` for the `:=` coherence, but this is exactly the bit to eyeball.

### 3.3 Optional: type elision in a known context

In `v := {x := 3; y := 4}` or a value argument, the target type is known, so the `TypeName` prefix could be optional. *Recommendation:* **require the prefix** initially (unambiguous, greppable, and it keeps the parser's job trivial — §6); add elision later only if it proves worth the lookahead.

## 4. Semantics

### 4.1 Unmentioned fields
- **Option (a) — zero-fill *(recommended)*.** Fields not named are set to the zero value (0/FALSE/NIL/empty). Safe, matches the fully-specified array literal's data image, and allows partial literals (`Config{verbose := TRUE}`).
- **Option (b) — require all fields.** Rejects a literal that omits any field. Safer against "forgot a field," but noisy for big records with sensible zero defaults. *Recommendation: (a).*

### 4.2 Field checks
Unknown field name, duplicate field, and type-incompatible value are compile errors (named binding makes all three precise and local).

### 4.3 Nested / child records
A field's `expr` may itself be a record (or array) literal, recursively — as in §3.1's `Line`/`Point`. No special rule: it is just an expression of the field's declared type.

### 4.4 Records with base types / methods / tags
A literal constructs a value of exactly `TypeName` (its static type); it does not choose a dynamic subtype. For **extensible** records used polymorphically, the DDR-013 **constructor** (`T.Init`, heap/pointer) remains the right tool; record literals target plain **value** aggregates. Open sub-point: whether a value-record literal of an extensible type should stamp the static type's tag (so a later VAR-param type test sees it). *Recommendation:* defer — value-record literals are for data aggregates; if a tagged value is needed, that is the constructor's job.

### 4.5 Pointers to records
A literal yields a **value**. To fill a heap record, assign a literal to the dereference (`p^ := Point{…}`) or use a constructor. A `NEW`-and-fill literal form (`Point{…}` producing a pointer) is **out of scope** — constructors already cover heap construction. Recorded as a possible future sugar.

## 5. Implementation sketch (why it is small)

- **Parser (shared ORP):** at the start of a factor, a qualident that resolves to a *record type* followed by `{` enters record-literal parsing (mirrors the existing `ARRAY OF T {…}` path). Parse `ident := expr` pairs, look each `ident` up as a field of `TypeName` to get its offset/type, `;`-separated.
- **Runtime form (both backends):** for `v := T{…}`, write each field's evaluated value directly into the target at its offset (reusing `Store`/`Field`); zero the unmentioned fields; as an argument/RETURN, build into a temp then copy (the backends already do record copy). No new codegen primitive.
- **`CONST` form:** all-constant fields → emit the record image into the data section by field offset (816, exactly like the array literal + the C compiler's positional record constant, plus name→offset lookup). LLVM `CONST` records could later use an LLVM struct global; runtime literals need nothing new on LLVM.
- **Effort:** parser work + name→offset resolution + field-store loop. Comparable to the array literal, plus name matching. The user's "not very difficult" is accurate for the runtime + 816-const forms.

## 6. Parsing note (no real ambiguity)

`{…}` alone is a **set** literal; `TypeName{…}` is a **record** literal — distinguished by the type-name prefix (§3.2 recommends keeping it required for exactly this reason). Additionally, `:=` inside braces cannot occur in a set (sets hold expressions/ranges), so the two never collide. The lookahead is one token past a qualident (`{`), and only when the qualident denotes a type.

## 7. Consequences

1. Records become writable as values — configuration, table rows, geometry, message structs — in a `CONST` and inline in code, on both backends for the runtime form.
2. Named fields mean **reordering a record declaration never silently corrupts a literal** (the positional array/record-const forms do not have this safety; this is the main reason to prefer named for records).
3. The `{…}` aggregate family (`ARRAY OF T {…}`, `TypeName{…}`) is consistent and small; no new keyword.
4. The value/heap division stays clean: **literals for value records, constructors (DDR-013) for heap objects.**

## 8. Decisions (ratified 2026-08-03)

1. **Scope** (§2): **S2 — general expression** (subsumes const-only).
2. **Binding operator** (§3): **`:=`**.
3. **Separator** (§3): **`;`**.
4. **Type prefix** (§3.3): **required** (elision may be added later as sugar).
5. **Unmentioned fields** (§4.1): **zero-fill**.

Canonical form: `TypeName{ field := expr ; … }`.

## 9. Implementation status (as-built, 2026-08-03)

Parser: `factor` detects a record-type qualident followed by `{` and calls a
`RecordLiteral` builder (`FindField` resolves each named field along the base
chain to its offset); the literal emits a zero-filled record image into the
data section, patching each constant field at its offset, and yields a `Const`
item. 816 `loadAdr` gained a `Const`-aggregate branch (address = SB + varsize +
offset), so `StoreStruct`/field access reach it.

**Works now (816):** named fields, any order, partial with zero-fill, nested
record literals, as an assignment RHS to any addressable record designator, and
as a `CONST` for imported/predeclared record types. Golden: `L3_RecordLit`.
Suite 140/142.

**Runtime-valued fields — implemented (2026-08-03), target-directed.** A record
literal on the RHS of an assignment fills the LHS *in place* rather than
producing a value: `RecordLitInto(target, rec)` zeroes the target via
`StoreStruct` from a zeroed data-section image (strict zero-fill, §4.1), then
`Field` + `Store`/`StoreStruct`/`StoreIface` per named field, recursing for
nested literals. No temporary and no held register — each `Field`/`Store`
re-derives a `Var` address, inheriting `Store`'s register discipline. Detected
by peeking the RHS with `ORB.thisObj()` (non-consuming) for a record type. Works
for **`Var`/`Par` targets** (`p := …`, `p.sub := …`, a record parameter):
runtime field values, out-of-order, partial (zero-filled), nested-with-runtime,
and reassignment all correct. (Bug found in bring-up: the backend `Field` does
not set `Item.type`, so the caller must `fi.type := fld.type` after it — else
the zero-image `StoreStruct` uses the *record's* size and over-writes adjacent
memory.)

**Still deferred, each with a specific cause:**
1. **`RegI` targets** (`arr[i] := T{…}`, `p^ := T{…}`) — the target address is a
   computed value in a register that must survive the zero + N field stores, but
   `Store` frees a `RegI` base and `loadAdr` mutates it in place, and that
   held-address discipline lives *inside* `ORG` (the parser only has the exported
   ops). Needs an `ORG`-internal held-address fill primitive (`rsav := RH` … inline
   writes … `RH := rsav`). Currently a clean "record literal target must be a
   variable or field" error.
2. **`CONST` of a same-module record type** — Oberon-07's declaration order is
   `CONST` then `TYPE`, so a `CONST` cannot name a record type declared in the
   same module. Only imported/predeclared record types work in a `CONST`. (The
   capability is intact for library-provided types; same-module constant records
   would need an ordering relaxation.)
3. **Nested *array* literal inside a record** — array literals live only in
   `CONST` position today, not general expression position, so an array-typed
   field can't yet take a literal. Nested *record* literals do work.
4. **LLVM backend** — has no const-data section (it uses global constants), so a
   record literal is a **clean compile error** there (`ORG_MakeRecordConst`
   Marks and yields a no-backend item; verified no crash), not miscompiled. A
   struct-global path could add real LLVM support later (§5).
