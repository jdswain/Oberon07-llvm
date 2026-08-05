# Design Decision Record 009: Error Model for Oberon-07

**Author:** Jason Swain
**Date:** 2026-07-16
**Status:** **Accepted** — mechanism (VAR error out-parameter) and error type (§4: pointer to extensible record, core `Errors` module) both ratified 2026-07-16
**Relationship to prior records:** Resolves the "Error model" open item in the parent record's §3 (*Design Decision Record: Object-Oriented Extensions to Oberon-07*, DDRs 001–007). Depends on DDR-001 (type-bound procedures, extensible-record dispatch) if §4's recommendation is adopted. Sits at step 5 of the parent's §5 sequencing: it must be settled before any library surface commits to a convention, because it is baked into every fallible signature (**P2**) and is miserable to change later.

---

## 1. Context

Oberon deliberately has no exceptions, and Oberon-07 functions return exactly one value, so a procedure that both produces a result and can fail needs a second channel. The parent record left the choice open, noting only that "a Go-style multiple-return or an explicit result type likely fits the culture better than `begin/rescue`."

Two facts ground the decision:

1. **The Wirth precedent is already in this codebase.** Project Oberon's own library idiom is a trailing `VAR res: INTEGER` out-parameter (`Files.Delete(name, res)`), and this project's runtime modules inherited it verbatim (`runtime/posix/Files.Mod`: `Delete`, `Rename`, `MakeDir`). Whatever is decided is a *refinement* of an idiom the code already speaks, not an invention.
2. **The object-model DDRs are now implemented** (001–008), so the error model may draw on type-bound procedures, extensible records with tags/guards, and interfaces — none of which existed when the Oberon System convention was set.

---

## 2. Decision — errors travel in a trailing `VAR` out-parameter

**Status: Accepted.**

A fallible procedure declares one additional, **final** parameter that receives the error; the ordinary result (if any) stays in the RETURN position:

```
PROCEDURE Open* (name: ARRAY OF CHAR; VAR err: Errors.Error): File;
PROCEDURE Close* (f: File; VAR err: Errors.Error);
```

Call sites read:

```
f := Files.Open(name, err);
IF err # NIL THEN ... END;
```

### 2.1 Conventions bundled with the mechanism

These are part of the decision; libraries rely on them being uniform (**P1** — one convention, learned once, no per-call-site deliberation):

- **C1 — Position and name.** The error parameter is the *last* parameter and is conventionally named `err`. One fallible procedure has exactly one error parameter.
- **C2 — Callee assigns on every path.** The callee assigns `err` on *every* return path — the success value on success, an error value on failure. The caller never needs to pre-clear it, and a stale in-value can never leak through. (This is the rule the compiler could later enforce; see §5.)
- **C3 — Success is the zero value.** "No error" is `NIL` (for a reference-typed error, §4) or `0` (for an integer-coded one). The test is always `IF err # NIL` / `IF err # 0` — never a comparison against a success constant.
- **C4 — Result value on failure.** When a function fails, its RETURN value is the type's zero value (`NIL`, `0`, `""`). Callers must not consume the result without checking `err`; the zero value makes the common misuse (dereferencing an unchecked result) fail fast rather than silently.
- **C5 — Infallible means no parameter.** A procedure that cannot fail does not take an `err` parameter. The parameter's presence *is* the documentation that the operation is fallible — signatures stay honest (**P4**'s spirit: expressed in the language, not in comments).

### 2.2 Rationale

- **It is the family idiom, upgraded.** Delphi/Turbo Pascal (`IOResult`), Project Oberon (`VAR res`), and this repo's own runtime all use out-parameter status. Choosing it means existing runtime modules migrate by *retyping* one parameter, not by reshaping every signature.
- **Zero mechanism.** No new syntax, no scanner/parser/codegen work, no runtime support, no impact on single-pass compilation (**P3**), identical cost on both backends — a `VAR` parameter is a pointer either way. The entire model is a *convention over an existing feature*, which is the cheapest kind of feature there is (**P1**).
- **Errors are values.** They can be stored, compared, passed on, logged, and (with §4) extended — no second control-flow regime, no invisible unwind paths through resource-managing code (which matters doubly under ARC, where an unwinding exception would have to run release-chains it cannot see).
- **Explicitness matches the culture.** Every fallible call is visibly fallible at the call site; the reader never wonders whether a call can throw.

---

## 3. Alternatives rejected

**A1 — Exceptions (`begin/rescue`, unwind).** Rejected outright, per the parent record's presumption. Exceptions create a second, invisible control-flow graph; every intervening frame must be unwind-safe, which under ARC means compiler-generated cleanup landing pads on both backends (large, complex codegen on the 65C816 especially). Value typically accrues to the library author; the cost — reasoning about invisible exit paths — is paid at every call site forever (**P1** at its worst). Also forecloses nothing: an `ASSERT`/trap facility for *unrecoverable* conditions is orthogonal and remains.

**A2 — Go-style multiple return values (`f, err := Open(name)`).** The semantics are exactly the chosen model; what it adds is *syntax* — tuple returns — which is signature-shaping (**P2**) and touches scanner, parser, symbol table, both code generators, and the `.smb` format. It would also be the language's only tuple, a one-off concept for one use case. The VAR mechanism delivers the same call-site experience minus the sugar. Rejected as paying a language-size cost for zero semantic gain. (If tuple syntax is ever wanted, it can be layered *on top of* this model later without changing any signature's meaning.)

**A3 — Error as the RETURN value, payload via VAR (`PROCEDURE Open(name...; VAR f: File): Errors.Error`).** The mirror image, and it has one genuinely attractive property: Oberon-07 forbids calling a function as a statement, so an error-as-result *cannot be silently discarded* — the compiler would force every caller to consume it (**P4**). Rejected nonetheless, on three grounds:
  1. It inverts the natural reading — the operation's *purpose* (the file) is demoted to an out-parameter, and expression-style composition (`x := Open(...)` feeding a chain) is lost for every fallible function.
  2. Half the library becomes functions-returning-errors that exist only to exploit the can't-discard rule; proper procedures (`Close`) gain nothing.
  3. The discipline it buys can be recovered *within* the chosen model by a targeted compiler check (§5) without contorting every signature.

**A4 — Result/sum types (`Result = Ok(T) | Err(E)`).** Requires variant types, pattern matching, and generics — three signature-shaping features this project has explicitly declined or deferred, resurrected for one use case. Contradicts the parent's generics position and **P3**. Rejected without further analysis.

---

## 4. Sub-decision — the error type

**Status: ratified 2026-07-16.** The mechanism (§2) is independent of this choice, but the type appears in every fallible signature, so it had to be ratified before library work (**P2**).

**Decision: a pointer to an extensible record, defined once in a core `Errors` module.**

```
MODULE Errors;
  TYPE
    Error*     = POINTER TO ErrorDesc;
    ErrorDesc* = RECORD
      code*: INTEGER;
      msg*:  ARRAY 64 OF CHAR
    END;

  PROCEDURE (e: Error) Code* (): INTEGER;
  BEGIN RETURN e.code END Code;
  ...
END Errors.
```

- **`NIL` = success** (C3). One machine word, ordinary pointer — identical cost to today's `VAR res: INTEGER` on the LLVM backend and one word cheaper than an interface fat pointer on the 65C816.
- **Extensible by the language's own means.** A library defines `PathError* = RECORD (Errors.ErrorDesc) path*: ... END`; callers who care narrow with the machinery that already exists — `IF err IS Files.PathError THEN err(Files.PathError).path ...` — and callers who don't care treat every error uniformly through the base. This is the role a `cause`/wrapping hierarchy plays in Go/Java, obtained from record extension for free.
- **Methods come along.** `ErrorDesc` is an ordinary record, so DDR-001 type-bound procedures (e.g. a `Describe` writing into a caller buffer) attach naturally, and extensions may override them.
- **No allocation on the error path is *required*.** A module may keep preallocated singleton errors (the ARC runtime's immortal-object sentinel, `rc < 0`, exists precisely for static instances) and assign the same one every time — important on constrained targets. Modules on hosted targets may allocate rich errors freely. Same signature either way.

**Alternatives for the sub-decision:**

- **A5 — `VAR res: INTEGER` codes (status quo).** Zero-cost and Wirth-blessed, but codes do not compose: two libraries' code spaces collide unless a central registry allocates ranges, which scales poorly and says nothing (**P4** — a bare `3` is a convention, not a checked meaning). No message, no context, no extension. Retained only as the migration starting point; the runtime's existing `VAR res` procedures should be retyped to the ratified error type in the same change that ratifies it.
- **A6 — An `Errors.Error` *interface* (DDR-008), Go-style.** Maximum decoupling — any record can be an error without extending a common base. But: a fat pointer (two words) in every fallible signature, where the 65C816 pays real zero-page cost on the *hot* path to support the *cold* one; and DDR-008 §7's nominal-conformance consequences apply (every error record must declare `IMPLEMENTS`), so the decoupling is smaller than it looks. The extensible record already provides the needed polymorphism with one word. Rejected unless a concrete need for base-class-free errors emerges before ratification.

---

## 5. Future compile-time tightening (non-blocking)

Two checks would move error discipline from convention to compiler, per **P4**; both are compatible with single-pass compilation and neither blocks library work:

1. **Definite assignment of `err` (C2):** in a procedure with a trailing `VAR err` parameter, warn when a return path neither assigns nor forwards it.
2. **Checked-before-use (C4):** warn when the result of a fallible function is dereferenced/consumed before `err` is inspected. This recovers the can't-discard property that made A3 attractive, without A3's signature inversion.

Neither is designed here; they are recorded so the convention is written with enforcement in mind (e.g. C1's fixed position and name make both checks trivially recognisable).

---

## 6. Consequences

1. Library work is unblocked: every fallible signature is `(..., VAR err: <ratified type>)`, results stay in RETURN position, `NIL`/`0` means success.
2. The runtime's existing `VAR res: INTEGER` procedures (`Files.Delete`, `Files.Rename`, `Files.MakeDir`, ...) are the migration surface; they should be converted when §4 is ratified, before any new library modules cite them as precedent.
3. No compiler change is required to adopt the model. The §5 checks are optional follow-ups.
4. `ASSERT` remains the tool for unrecoverable conditions/programming errors; the error model is for *expected, recoverable* failure. The boundary (trap vs. error) is a library-design judgement recorded per-module, not a language rule.

---

## 7. Amendments this record makes to the parent DDR

- **§3 "Error model" open item →** resolved: **VAR error out-parameter** (this record, Accepted), with the error-type sub-decision (§4 here) as the residual item to ratify before library implementation.
- **§5 Sequencing step 5** ("Error model — decide before any library surface commits") → decided; step 5 becomes ratification of §4 plus migration of the runtime's `VAR res` procedures.
