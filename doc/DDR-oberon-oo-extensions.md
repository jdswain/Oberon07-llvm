# Design Decision Record: Object-Oriented Extensions to Oberon-07

**Author:** Jason Swain
**Date:** 2026-07-14
**Scope:** Language extensions to a personally-owned Oberon-07 toolchain (two backends: a 65C816 native code generator and an LLVM-based generator), undertaken *before* a body of library modules is written.
**Overall status:** Core object model decisions accepted; several signature-shaping decisions still open (see §3).

---

## 1. Context and Guiding Principles

The base language is Oberon-07, which — unlike the Oberon-2 revision — does not provide type-bound procedures; dynamic dispatch must otherwise be simulated with procedure-typed fields in records. The motivating goal is to recover Java-style object-oriented programming while preserving the properties that make Oberon worth using: minimalism, fast single-pass compilation, small native code, and a runtime small enough to run on constrained targets (the same environment that hosts the author's 65C816 and microkernel work).

The following principles governed every decision below and should govern future ones.

**P1 — Feature cost is dominated by per-use-site decision cost.** The expense of a feature is not its implementation or learning cost but the recurring choice it imposes on the programmer at every relevant line. Value typically accrues once, to the library author; complexity is paid by every reader forever. A feature that "adds value and equal complexity" therefore often nets negative.

**P2 — Distinguish signature-shaping features from sugar.** Features that change the shape of type signatures (the object model, interfaces, generics, closures, the error model, constructors, super) propagate into every library API and cannot be retrofitted without rewriting those APIs and their callers. Sugar over expressions and statements (string interpolation, ranges, collection literals, keyword arguments) never appears in a signature and can be added later without breaking anything. **Decide signature-shaping features before writing libraries; defer sugar.**

**P3 — Preserve fast single-pass compilation.** No extension may compromise the compile-at-I/O-speed property. This constrains, in particular, any approach to generics.

**P4 — Prefer compile-time checks to conventions.** Where a naming convention and a compiler-checked marker express the same intent, choose the marker: the compiler cannot verify a convention, so a typo silently produces the wrong program.

**P5 — Learn from the successful branches without inheriting their bloat.** Go (Oberon's direct descendant via Griesemer) and Object Pascal / Delphi both kept Oberon's fast native compilation while adding an object model, and both then accreted weight (Go's multi-megabyte runtime; Delphi's RTTI, published properties, and proliferating string types). They serve as proof the design point is reachable *and* as a cautionary tale about where it drifts when features win every argument.

---

## 2. Decisions

### DDR-001 — Extend Oberon-07 in place; do not port to Oberon-2
**Status:** Accepted

**Context.** The desired object model (methods, single inheritance, `IS`/type-guard) is the Oberon-2 model. The obvious move is to "port to Oberon-2."

**Decision.** Add *type-bound procedures* to the existing Oberon-07 compilers as a surgical feature. Do **not** perform a dialect port to Oberon-2.

**Rationale.** Oberon-07 is a later, independent revision, not a subset of Oberon-2. A dialect port would reconcile a whole basket of differences that are not wanted, and would undo Oberon-07 revisions that are agreed improvements (notably the simplified numeric-type set, versus Oberon-2's `SHORTINT`/`LONGINT`/`LONGREAL` family). The single load-bearing feature actually needed is type-bound procedures.

**Consequences.**
- Deliberately **not** re-added: `WITH` (the type-guard expression `v(T)` already covers it), `LOOP`/`EXIT`, and Oberon-2 read-only export (the trailing `-`). Each is reconsidered only if independently missed.
- Implementation touches parser, symbol table, and code generator, but **not** the GC or memory model. The per-record runtime type descriptor Oberon-07 already emits (type tag + extension chain, powering `IS` and `v(T)`) is *extended*, not replaced.

**Implementation outline.**
1. *Parser:* optional receiver on procedure declarations, `PROCEDURE (r: T) M(...)`; allow the `.` selector to resolve bound procedures as well as fields.
2. *Symbol table:* per-record method table, computed by walking the extension chain (inherited methods copied down; an override replaces its slot); `p.M` lookup searches the chain.
3. *Override checking:* a matching name in an extension must have an identical signature (see DDR-002 for how the intent is marked).
4. *Code generation:* extend the existing type descriptor with a vtable, laid out so inherited slots keep their index in extensions (a base-typed call hits the same slot). Dynamic `p.M(...)` = load descriptor, index slot, indirect call; statically-known cases devirtualise to a direct call.
5. *Semantics:* dispatch is on the receiver's dynamic type (so polymorphism arrives through pointer receivers; a record-value receiver's dynamic type equals its static type). A super-call convention is required (see DDR-006).

---

### DDR-002 — Explicit `override` marker
**Status:** Accepted

**Context.** Oberon-2 makes overriding implicit: a matching signature *is* an override. A typo in the signature then silently declares a *new* method rather than the intended override, and the compiler cannot warn, because it cannot distinguish the mistake from intent.

**Decision.** Require an explicit `override` modifier on any type-bound procedure that redefines a base method, layered on top of the Oberon-2 identical-signature rule.

**Rationale.** Closes a real and unpleasant bug class at compile time (as adopted independently by Delphi, Java `@Override`, and C++ `override`). Per **P4**, this is *more* in the Oberon spirit than the implicit rule, despite Wirth not having done it — it is pure compile-time error-catching with no runtime cost.

**Consequences.** Adds one declaration modifier. Surface syntax for it is covered by DDR-007.

---

### DDR-003 — Guaranteed initialisation via type-bound initialisers
**Status:** Accepted

**Context.** Oberon's `NEW(p)` followed by a by-convention `p.Init(...)` lets an uninitialised object escape into use — a genuine hole. Full constructor apparatus (virtual constructors, initialisation ordering, exceptions-in-constructors) is more than is wanted.

**Decision.** Introduce type-bound *initialisers* that combine allocation and initialisation, marked by an `init` modifier (not a naming convention, per **P4**). An `init` procedure: has no receiver at the call site; allocates fresh storage; binds `SELF` to it; is callable on the type rather than an instance; is non-returning-as-a-value in the ordinary sense; and is **not** callable as a normal method — the only way to reach it is through allocation.

**Rationale.** Ties allocation to initialisation so an uninitialised object cannot be produced, without importing the full constructor machinery.

**Consequences / bundled sub-decisions.**
- **One initialiser body per type** in the no-overloading sense; distinct constructors are distinguished by *name*, not signature (see DDR-004).
- **Inheritance rule:** an extension inherits the base initialiser unless it declares its own; if it declares its own, it is responsible for an explicit base-initialiser call. This reuses the super-call convention of DDR-006 — no new machinery.
- Supersedes the naïve `NEW(p, args)` route (see DDR-004/005).

---

### DDR-004 — Named type-bound constructors (Delphi-style)
**Status:** Accepted

**Context.** Combining `NEW` and init raises two problems: parameters must be threaded through the allocator (`NEW(p, args)`, clumsy), and Oberon has no overloading, which would cap a type at a single constructor signature.

**Decision.** Express construction as a **named, type-qualified call** that allocates and initialises:
```
p := HTTPConnection.CreateWithAddress(addr)
```
Multiple constructors are distinguished by name (`CreateWithAddress`, `CreateFromStream`, `CreateDefault`), each an `init`-marked procedure per DDR-003.

**Rationale.** This is the idiomatic Object Pascal named-constructor model — independent arrival at the mechanism from the family's commercially successful branch (**P5**). It dissolves both problems at once: allocation-plus-init is a single expression with no overloaded `NEW`, and the absence of overloading stops mattering because constructors are keyed by name.

**Consequences.**
- **Alternative rejected:** `NEW(p, args)` — rejected as clumsy and as forcing the overloading question.
- **Accepted trade-off (eyes open):** descriptive constructor names reintroduce overloading "through the back door" in the Objective-C style (`CreateWithAddress`, `CreateWithAddressAndPort`, …). This is expressive but can sprawl (**P1**); it is a chosen taste, not a free consequence.

---

### DDR-005 — Unifying rule: type-qualification forces static binding
**Status:** Accepted

**Context.** Two proposed features — named constructors (DDR-004) and super calls (DDR-006) — appear to share a `Type.Method` / `instance.Type.Method` surface but are not the same shape (one is receiverless, one has a receiver).

**Decision.** Adopt a single underlying rule that unifies them: **a type name used as a qualifier means "resolve this call statically, in that type."** Construction is the receiverless case (no object exists yet, so the type is named directly); super is the receiver case (an object exists, but a specific ancestor's version is wanted, non-virtually).

**Rationale.** The rule is teachable in one sentence and prevents a later third case that does not fit. It also has a concrete efficiency pay-off: type-qualified calls are *direct* calls (no descriptor load, no slot index) — trivially inlinable on the LLVM backend, and a real cycle/zero-page saving on the 65C816, where indirection is expensive.

---

### DDR-006 — Super calls, limited to a single (immediate) level
**Status:** Accepted

**Context.** A super mechanism is required so an override can invoke the base version. The initial proposal (`connection.TCPConnection.connect()`) allowed naming *any* ancestor.

**Decision.** Provide super as a distinct construct, **restricted to the immediate base type only**. Because a type's immediate base is unique, the call needs no disambiguation; the preferred surface form is therefore a bare keyword (e.g. `SUPER.connect()`) rather than the type-qualified `instance.Base.connect()`.

**Rationale.**
- **Skip-level calls are a footgun:** naming an arbitrary ancestor allows bypassing an intermediate override and violating that intermediate type's invariants. Restricting to the immediate base removes this by construction.
- **Refactor robustness:** an explicit ancestor name encodes the hierarchy's shape into every call site, so inserting a type into the hierarchy silently mis-targets existing calls with no diagnostic. A single-level keyword automatically means "my (new) immediate parent." Since there is exactly one legal target, naming the base is pure redundancy that only adds fragility.
- The type-qualified form (DDR-005) is retained for the *constructor* case, where there is no receiver and the type genuinely must be named.

**Consequences / alternatives rejected.**
- **Arbitrary-ancestor super:** rejected (footgun + fragility), notwithstanding rare legitimate uses.
- **Type guards as a super mechanism:** rejected on two independent grounds.
  1. *Wrong direction.* Oberon's guard `v(T)` only narrows — it requires `T` to be an *extension* of the static type of `v` (a downcast). Super needs to view the receiver as its *base*; since `Base` is not an extension of `Derived`, `r(Base)` is not even a legal guard.
  2. *Wrong axis.* A guard changes only the *static* type of an expression, whereas type-bound calls dispatch on the *dynamic* type, which no guard or cast touches. `r(Base).connect()` would still dispatch to the derived override; written inside that override it recurses infinitely. Super is a *binding* construct (force static dispatch), not a *typing* construct.
  - This matches every language in the space: Java's upcast `((Base)o).m()` still dispatches virtually (hence `super` is a keyword); C++ requires the qualified name `o.Base::m()`, not a cast.

---

### DDR-007 — Declaration-modifier syntax
**Status:** Ratified 2026-07-14

**Context.** Oberon-07 already uses a trailing `*` sigil for visibility (export). A proposal considered reusing sigils for the new modifiers: `+` for init, `-` for override. The earlier decisions (DDR-001/002/003/006) name the *features*; this decision fixes their concrete surface. The previously recorded recommendation (keywords, not sigils) is ratified and made precise below.

**Decision.**

**D7.1 — `*` remains the sole sigil.** No new sigils are introduced. All new modifiers are upper-case reserved words, extending the keyword vocabulary rather than the sigil vocabulary. The rationale recorded at recommendation time carries forward unchanged:
- `-` is reserved in the Oberon-2 lineage for read-only export; reusing it burns that symbol and misleads anyone with Oberon-2 muscle memory.
- `*` and a dispatch sigil would compete for the same trailing-identifier slot (a method may be both exported *and* an override → `M*-`), forcing an ordering rule for stacked sigils. With keyword modifiers positioned away from the identifier, no such rule exists.
- Sigils for init/override would introduce a *second* semantic category (dispatch/lifecycle) into a vocabulary that currently means only visibility, spending the "small, already-learned set" capital that makes `*` tolerable (**P1**).
- `override` is written rarely and read as a safety assertion; legibility outweighs keystroke-saving.

**D7.2 — Three new reserved words: `INIT`, `OVERRIDE`, `SUPER`.** Upper-case, matching the entire existing keyword vocabulary (a lower-case second lexical class of keyword is rejected). `SUPER` is DDR-006's construct; its *reservation* is ratified here so the keyword set is fixed in one place. A survey of all 677 `.Mod` sources in the tree found **zero** occurrences of any of the three as identifiers (Oberon is case-sensitive; the conventional `Init` procedure name, present in 35 modules, is unaffected). The reservation is free today and only gets more expensive once libraries exist (**P2**).

**D7.3 — Receiver syntax is the Oberon-2 form.** A parenthesised receiver section between `PROCEDURE` and the procedure name:

```
PROCEDURE (c: Connection) Connect* (timeout: INTEGER): BOOLEAN;
```

The receiver is either a value parameter of pointer-to-record type or a `VAR` parameter of record type (dispatch semantics per DDR-001 §5). This is the established syntax of the family's own object-model revision; inventing a variant would cost novelty and buy nothing.

**D7.4 — `INIT` leads; `OVERRIDE` trails.** `INIT` appears immediately after `PROCEDURE`; `OVERRIDE` appears at the end of the heading, after the formal parameters and result type:

```
PROCEDURE INIT (c: Connection) CreateWithAddress* (addr: Address);
PROCEDURE (c: HTTPConnection) Connect* (timeout: INTEGER): BOOLEAN OVERRIDE;
```

The asymmetry is deliberate, not an oversight. As noted at recommendation time, init and override are different *kinds* of thing, and uniform placement would misleadingly present them as two flavours of one thing:
- `INIT` changes what the declaration *is* (an allocator-hooked constructor with a different call surface), so it is announced before anything else is read — the same shape as Delphi's leading `constructor` keyword (**P5**).
- `OVERRIDE` is an assertion *about the completed signature*, so it is written where it is checked: after the signature — the same position as Delphi's trailing `override` directive and C++'s trailing `override` (**P5**).
- Parsing benefits fall out for free: a leading `INIT` is known before the procedure object is created, and a trailing `OVERRIDE` arrives exactly when the compiler is ready to compare signatures against the base (**P3**, single-pass).

**D7.5 — No `SELF` keyword.** DDR-003's "binds `SELF`" was semantic shorthand, refined here with no semantic change: the declared receiver identifier names the instance, in ordinary methods and in initialisers alike. One binding rule, one way to name the receiver, no implicit identifier.

**D7.6 — The constructor qualifier is the pointer type.** Operationalising DDR-004/005: in `p := HTTPConnection.CreateWithAddress(addr)`, the qualifier is the pointer type named in the initialiser's receiver declaration, and the type of the constructor-call expression is that pointer type.

**Grammar** (deltas to the Oberon-07 report; `identdef = ident ["*"]` is unchanged and continues to carry visibility):

```
ProcedureHeading = PROCEDURE [INIT] [Receiver] identdef [FormalParameters] [OVERRIDE].
Receiver         = "(" [VAR] ident ":" qualident ")".
SuperCall        = SUPER "." ident [ActualParameters].
```

**Worked example.**

```oberon
TYPE
  Connection*         = POINTER TO ConnectionDesc;
  ConnectionDesc*     = RECORD addr: Address END;
  HTTPConnection*     = POINTER TO HTTPConnectionDesc;
  HTTPConnectionDesc* = RECORD (ConnectionDesc) host: ARRAY 64 OF CHAR END;

PROCEDURE INIT (c: Connection) CreateWithAddress* (addr: Address);
BEGIN c.addr := addr
END CreateWithAddress;

PROCEDURE (c: Connection) Connect* (timeout: INTEGER): BOOLEAN;
BEGIN ...
END Connect;

PROCEDURE INIT (c: HTTPConnection) CreateWithAddress* (addr: Address);
BEGIN SUPER.CreateWithAddress(addr); c.host := ""
END CreateWithAddress;

PROCEDURE (c: HTTPConnection) Connect* (timeout: INTEGER): BOOLEAN OVERRIDE;
BEGIN ...; RETURN SUPER.Connect(timeout)
END Connect;

...
conn := HTTPConnection.CreateWithAddress(addr);
```

**Constraints (all compile-time, per P4).**
- `INIT` and `OVERRIDE` are mutually exclusive; a derived initialiser is a *new named constructor* (DDR-003/004), never an override.
- `INIT` requires a receiver, and the receiver must be the pointer form (a fresh heap instance is being constructed).
- An `INIT` heading has no result type; the constructed instance is the value of the constructor-call expression, typed per D7.6.
- `OVERRIDE` with no matching base method is an error; a matching base-method name *without* `OVERRIDE` is likewise an error (DDR-002, both directions).
- `SUPER` is legal only inside a type-bound body, and resolves only in the immediate base (DDR-006).

**Alternatives rejected.**
- **Sigils (`+` init, `-` override):** per D7.1 rationale.
- **Uniform trailing placement for both keywords:** presents an allocator-hooked role and a compile-time assertion as two flavours of one thing; also forces the parser to reinterpret a mostly-parsed ordinary heading as a constructor.
- **Uniform leading placement (`PROCEDURE OVERRIDE ...`):** makes an assertion read like a declaration kind, which override is not.
- **A `SELF` keyword:** a second way to name the receiver, and an implicit identifier in a language that has none (per D7.5).
- **Lower-case modifier keywords (`init`, `override`, as in earlier working text):** a second lexical class of keyword for no benefit.

**Consequences.**
- Scanner: three tokens, appended after the existing `ORS_weak` slot (outside the ranged token tests, same non-breaking strategy).
- After `PROCEDURE`, the tokens `*` (existing interrupt marker), `INIT`, `(`, and an identifier are mutually distinguishing with one-token lookahead — single-pass parsing preserved (**P3**).
- Zero migration cost, measured against every module in the tree as of this ratification.

---

## 3. Open Decisions (resolve before library implementation)

These are signature-shaping (**P2**) and therefore must be settled before library APIs depend on them.

- **Interfaces.** *Resolved 2026-07-14 by DDR-008 (`doc/DDR-008-oberon-interfaces.md`): **nominal, declared-conformance** interfaces.* The earlier "(structural, Go-style)" framing is superseded. Interfaces — not the class machinery — are the genuinely missing polymorphism feature: single record extension gives only a rigid tree, whereas most real reuse needs "any type that can do X." Type-bound procedures (DDR-001) are the prerequisite, **not** the destination. Interfaces handle *input* polymorphism (many types → one function) and are sufficient for algorithms that only consume via method calls (e.g. sort by a `Comparable`) and for strategy/callback/visitor patterns. Definition is RECORD-like with method signatures only; inclusion is by naming (flattening union); a record declares conformance via `IMPLEMENTS`, checked entirely at compile time. *Residual open item (DDR-008 §7.3):* nominal conformance forecloses retroactive conformance on foreign types — decide, before modules depend on library boundaries, whether the adapter-record workaround suffices or a narrow external conformance assertion is wanted.
- **Generics.** *General system rejected; narrow option open.* Full user-facing generics fight both minimalism and single-pass compilation (**P3**) — monomorphisation bloats code and slows compilation; erasure boxes. Interfaces do **not** substitute for generics on collections: retrieval still returns the interface type (downcast on the way *out*), homogeneity is unenforced, and — decisively for this project's efficiency goals — value types (e.g. `INTEGER`) must be boxed to implement an interface, one heap allocation per element. Go's own trajectory (interfaces from day one; generics added in 2022 specifically for the typed-container case) is direct evidence. **Recommended:** generics *only* for a small set of compiler-provided collection types (parametric array/list/map), giving type-safe, unboxed containers — ~80% of what generics are wanted for — without a general type-parameter system and without library authors gaining a powerful abstraction to overuse.
- **Error model.** Baked into every signature; miserable to change later. Oberon deliberately has no exceptions. A Go-style multiple-return or an explicit result type likely fits the culture better than `begin/rescue`. **To be decided.**
- **Closures.** Highest-leverage expressiveness feature, and a prerequisite *only if* libraries expose an `each`/`map`-style internal-iteration protocol (the callback type then appears in the signature). The existing GC makes the captured-environment allocation acceptable. **Decide iff an iteration protocol will be exposed.**

---

## 4. Deferred (non-breaking; add any time)

Per **P2**, these are sugar over expressions/statements, appear in no signature, and can be added after libraries exist without breaking them. Explicitly parked so they do not distract from §2–§3:

- String type improvements and interpolation (replacing 0X-terminated `ARRAY OF CHAR` friction)
- Ranges (`1..n`) for loops and slicing
- Collection/aggregate literals
- Default and keyword arguments

**Explicitly out of scope (rejected in principle):** open classes, `method_missing`/`define_method`-style metaprogramming, uniform "everything is an object", heavy runtime reflection — all incompatible with module-in-isolation reasoning and the value/reference distinction, and all spending exactly the guarantees Oberon exists to provide.

---

## 5. Recommended Sequencing

1. **Object model** — implement DDR-001 (type-bound procedures) with DDR-002 (`override`).
2. **Initialisation/construction** — DDR-003 + DDR-004 + DDR-005 (they are one mechanism).
3. **Super** — DDR-006 (rides on the base-init call convention already needed in step 2).
4. **Interfaces** — implement DDR-008 (nominal, declared conformance; the structural-vs-nominal question is closed). The runtime representation (DDR-008 §6, fat vs plain pointer) is a deferred, non-blocking ABI item that may be settled per backend after libraries. Needed before collection/IO library APIs.
5. **Error model** — decide (§3) before any library surface commits to a convention.
6. **Closures + iteration protocol** — only if the library design exposes internal iteration.
7. **Built-in generic collections** — decide (§3); implement if adopted.
8. **Sugar** (§4) — at leisure, after libraries, non-breaking.

DDR-007 was ratified 2026-07-14; step 1 is unblocked.
