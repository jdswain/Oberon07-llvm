# Design Decision Record 014: Concurrency Model

**Author:** Jason Swain
**Date:** 2026-07-28
**Status:** **Accepted; `Spawn`/`Yield` first cut implemented 2026-08-04 (LLVM/POSIX).** Mechanism: cooperative I/O concurrency, per-backend schedulers (§2.1; preemption at the process boundary only, DDR-018 §5.1). Surface: **library `Spawn`/`Chan`** (§5, decided 2026-08-03); the Active Oberon grammar is the documented non-breaking upgrade path. `Tasks` (Spawn/SpawnTask/Yield/Run) + a `ucontext` scheduler now exist and drive `Net.Serve` concurrently — see §8. Still open: **`Chan`** (channel element typing — deferred with narrow-generics), cancellation handle, and the stackless-async fallback for wasm-without-JSPI (§5).
**Relationship to prior records:** New sibling to DDRs 001–013. It is a *language + runtime* extension (the first since the OO work), so it touches the parent OO record's spirit (minimalism, small runtime, fast single-pass compilation) directly. It consumes DDR-011 (the platform layer that must supply non-blocking I/O and, optionally, threads) and DDR-012 (OS16 already has processes/IPC; a user-level model must map onto them). It is consumed by DDR-015/016/017.
**External prior art:** **Active Oberon** (Gutknecht & Reali, ETH; the A2/Bluebottle SMP OS) is the authoritative in-family answer — active objects, `{EXCLUSIVE}` monitors, `AWAIT(cond)`. It is preemptive shared-memory (wasm-hostile as-is), but its *surface* is reusable over a cooperative scheduler; see Option 6 (§4).

---

## 1. Context

The target workload — an `oed` client that reads and syncs files to an Oberon server — needs to do several things at once: a server must accept a new connection while still serving existing ones; a client must sync in the background without freezing the editor. That is **concurrency** (progress on many tasks) and specifically **I/O concurrency**, not necessarily **parallelism** (many CPUs at once). The distinction matters enormously for how large the extension has to be.

The hard constraint is the runtime spread:

| Runtime | Threads | Blocking I/O | Native model |
|---|---|---|---|
| POSIX / macOS | yes (pthreads) | yes | threads + blocking sockets |
| iOS | yes | yes | GCD / threads |
| Android | yes | yes | threads |
| **wasm (browser)** | **main thread only**; Workers have **separate heaps** (message-passing), shared memory needs SharedArrayBuffer + COOP/COEP | **no** — everything is the event loop | Promises / callbacks / `async` |
| OS16 (DDR-012) | processes + IPC | kernel-dependent | server IPC |
| 65C816 | single core | — | cooperative only |

Oberon has **no concurrency in the language today.** Whatever we add is the first such extension, and the parent record's constraints (minimal language, small runtime, single-pass compilation, constrained targets) apply with full force. The wasm row is the one that decides the shape: a design that assumes OS threads and blocking sockets cannot run in the browser at all.

## 2. Framing — what we actually need (and don't)

Two observations shrink the problem:

1. **The workload is I/O-bound, not CPU-bound.** A sync server spends its time waiting on sockets and disk, not computing. It needs to *interleave* waiting tasks, which a single scheduler thread with non-blocking I/O achieves. True multi-core parallelism buys little here and costs a great deal (shared-memory data races, locks, a memory model — none of which Oberon has today).
2. **Cooperative scheduling removes the hardest part.** If tasks only switch at explicit I/O/yield points, there are **no pre-emptive data races**: shared state is safe between yields. This eliminates the need for a memory model, locks-as-language-feature, and most of what makes concurrency a "large" extension.

So the recommended framing is: **add I/O concurrency as the baseline; treat multi-core parallelism as a separate, deferred capability** with its own record if it is ever wanted.

### 2.1 One surface, per-backend schedulers (the 816 is not held to wasm's limits)

An explicit principle, adopted 2026-08-03: the concurrency **surface** is shared, but its **scheduler is chosen per backend**, exactly as the OO ABI (DDR-013) and the platform layer (DDR-011) already diverge per target. The 816 must **not** be constrained to wasm's model — it has its own constraints and, with the custom Verilog core (DDR-018), its own strengths (cheap context switch, stacks/DP freed from bank 0, per-process banks).

- **Surface (shared):** Active Oberon `{ACTIVE}` / `{EXCLUSIVE}` / `AWAIT` (Option 6).
- **816 / OS16 scheduler:** the kernel preempts **processes** (a runaway process must not hang the machine), but per DDR-018 §5.1 *in-process tasks are cooperative* — preemption stops at the process boundary, and processes share no mutable state (own banks, DDR-018 §4).
- **wasm / LLVM scheduler:** **cooperative** event-loop; `AWAIT` re-evaluates at yield points.
- **So `{EXCLUSIVE}` is free within a process on every backend** (cooperative in-process) and there is no cross-process shared state to guard. It stays in the surface as intent + future-proofing: it becomes load-bearing only if in-process preemption is ever adopted (DDR-018 §5.1 rejected alternative) or a multi-core parallel scheduler lands (§4 Option 5).

The source is written to the preemptive contract (guard shared state with `{EXCLUSIVE}`) and degrades to nothing on cooperative wasm — which is precisely why the Active Oberon surface is the correct shared abstraction. Note (DDR-018 §5.1, decided): on the 816 preemption stops at the **process** boundary — *in-process* tasks are **cooperative**, as on wasm. So `{EXCLUSIVE}` is free within a process on every backend, and only distinct processes (which wasm lacks) are preempted; the in-process programming model is uniform across all backends.

## 3. Decision axes

The model is the product of four choices. §4 gives concrete option bundles; these are the axes they vary on.

- **A. Unit of concurrency.** OS thread (1:1) · **green task / coroutine** (M:1 or M:N, user-scheduled) · explicit async callback (invert control).
- **B. Coroutine mechanism (if green tasks).** **Stackful** (each task owns a stack; yield = swap stacks; runtime-only, no compiler change, no function colouring) · **stackless** (compiler transforms `async` procedures into state machines; no per-task stack; colours the API; large compiler work).
- **C. Communication & synchronization.** Shared memory + explicit locks · **channels (CSP)** · pure message-passing (actors) · **object monitors + `AWAIT(cond)`** (Active Oberon — structural mutual exclusion, declarative conditions, no explicit locks). Note `AWAIT` is *independent* of D: it works under a cooperative scheduler (re-evaluate awaited conditions at each yield) as well as under preemption.
- **D. Parallelism.** Single scheduler thread (concurrency only) · M:N over a thread pool (real parallelism, needs a memory model).

## 4. Options

### Option 1 — Cooperative green tasks, stackful, single scheduler thread, channels *(recommended baseline)*

A = green task, B = **stackful**, C = **channels**, D = single thread.

`Spawn(P)` starts a task; tasks run until they block on I/O or a channel or call `Yield`; a runtime scheduler resumes them. Code reads as ordinary **blocking** code (`n := conn.Read(buf)`), but the "block" is a stack-swap back to the scheduler, which drives non-blocking platform I/O (DDR-011 `select`/`poll`/`epoll`/`kqueue` on native, the event loop on wasm) and resumes the task when ready. Channels (a small `Chan` interface or built-in) carry values between tasks; because scheduling is cooperative, a channel is just a queue + task-wake, no locks.

- **Language impact:** *small.* Add `Spawn`/`Yield` (library or two keywords) and a `Chan` type. **No compiler transform, no function colouring** — the blocking-looking API is the actual API.
- **Runtime impact:** a scheduler + a stack-swap primitive per target (a few dozen instructions of asm: save callee-saved regs + SP, load the other). Native: trivial. OS16: maps to a kernel primitive or user fibers. 816: user fibers, cheap.
- **wasm cost — the catch:** wasm's call stack is protected; you cannot swap SP from user code. Stackful coroutines on wasm require **Asyncify** (a whole-program stack-unwinding transform at wasm-link time — works today, ~size/speed overhead) **or JSPI** (JS Promise Integration — native stack switching, now shipping in browsers, the clean path). So this option is "free" on native and "needs Asyncify or JSPI" on wasm. See DDR-016.
- **Verdict:** smallest language change, uniform blocking API everywhere, the CSP model fits servers cleanly. The wasm implementation is the only wrinkle, and JSPI removes it.

### Option 2 — Stackless async/await (compiler-transformed)

A = green task, B = **stackless**, C = channels or futures, D = single thread.

`async PROCEDURE` and `await` expression; the compiler rewrites each async procedure into a resumable state machine (CPS / heap-allocated frame). No per-task stack; maps *natively* onto the wasm event loop (no Asyncify/JSPI needed).

- **Language impact:** *large.* A new procedure colour (`async`), an `await` operator, and a **state-machine transform in ORG/ORP** on both backends — comparable in size to the whole OO effort. Function colouring infects every caller of an async procedure (the well-known "async is contagious" cost).
- **Runtime impact:** small (no stack-swap; frames are heap records the GC already handles).
- **wasm cost:** zero — this *is* the event loop.
- **Verdict:** the cleanest wasm story and no per-task stacks, but the biggest language change and it colours the API — against the "easy, high-level, minimal" goal. Reasonable only if wasm parity without JSPI is a hard requirement.

### Option 3 — OS threads + blocking I/O (1:1)

A = OS thread, C = shared memory + locks, D = M:N (real parallelism).

Expose native threads directly; blocking sockets; locks/condition variables in a `Threads` module.

- **Language impact:** small syntactically, but forces a **memory model** and locks into the library, and pre-emption reintroduces data races (the thing Option 1 avoids by construction).
- **wasm cost:** **fatal.** No blocking on the main thread; Workers are separate heaps. A shared-memory threaded server simply cannot run in the browser. This option abandons the wasm target for the server.
- **Verdict:** rejected as the *portable* model. May still appear *underneath* Option 1/4 as an optional M:N parallel scheduler on native only (§4, Option 5).

### Option 4 — Explicit async callbacks (event loop exposed)

A = callback, invert control: `conn.OnReadable(handler)`.

- **Language impact:** none (it's a library).
- **wasm cost:** zero (native model).
- **Verdict:** rejected as the *primary* surface — callback-style servers are exactly the "hard to write cleanly" inversion the user wants to avoid ("easy to use and high level"). It is, however, the substrate every option lowers to on wasm, and a fine *escape hatch* for a raw event handler.

### Option 5 — Add parallelism later (deferred capability, native only)

Independent of A–C: keep the cooperative scheduler (Option 1) but run **several scheduler threads** over the task set on native, with channels as the only cross-thread communication (no shared mutable state in the language). This is the Go model. It needs a memory model *only for the runtime*, not the language, because user code communicates through channels.

- **Verdict:** **defer.** Record it as the growth path so Option 1's API (Spawn/Chan) is designed not to preclude it, but do not build it until a CPU-bound workload demands it.

### Option 6 — Active Oberon active objects (surface) over a cooperative scheduler *(strong contender for the surface)*

This is not a competitor to Option 1 on axes A/B/D — it is a **surface** decision (axis C, plus how a task is spawned) that reuses the most authoritative in-family prior art. Active Oberon (Gutknecht & Reali; the A2/Bluebottle SMP OS) made concurrency **object-centric**:

- **Active objects** — an object body marked `{ACTIVE}` runs as its own activity; creating the object starts it. The unit of concurrency is the object, not a free `Spawn(P)`.
- **`{EXCLUSIVE}`** — a procedure/block so marked is a monitor region; at most one activity is inside an object's exclusive code at once. **No explicit locks in the language** — mutual exclusion is structural.
- **`AWAIT(cond)`** — inside an exclusive region, block on a *boolean condition*, releasing exclusivity; the runtime resumes when `cond` holds (re-checked whenever an activity leaves an exclusive region). This replaces condition variables and their lost-wakeup class of bug.

```
  TYPE Server = OBJECT
    VAR pending: INTEGER;
    PROCEDURE Handle(c: Conn);
    BEGIN {EXCLUSIVE} INC(pending); ... END Handle;
  BEGIN {ACTIVE}                    (* an accept loop as the object's activity *)
    LOOP c := l.Accept(err); ... END
  END Server;
```

The crucial move for *this* project: **keep Active Oberon's `{ACTIVE}` / `{EXCLUSIVE}` / `AWAIT` surface, but back it with the cooperative single-thread scheduler of Option 1 instead of preemptive SMP.** Active Oberon itself is preemptive shared-memory — the exact model wasm cannot run (DDR-016) — but the *surface* does not require preemption: `{EXCLUSIVE}` under cooperative scheduling is nearly free (a region simply doesn't yield), and `AWAIT` re-evaluation happens at yield points. So the ergonomics transfer to the browser event loop that the preemptive implementation could never reach.

- **Language impact:** *moderate.* Object bodies with modifiers, and `AWAIT` — a real grammar addition (bigger than Option 1's library `Spawn`, far smaller than Option 2's async transform). `{EXCLUSIVE}` is a no-op marker under cooperative scheduling but documents intent and stays correct if Option 5 parallelism is ever added.
- **Runtime impact:** same stackful scheduler as Option 1; `AWAIT` needs a condition-recheck list.
- **wasm cost:** identical to Option 1 (JSPI/Asyncify for the stack swap).
- **Verdict:** the **recommended *surface*** if a grammar change is acceptable — it reuses a proven Oberon-family design, reads beautifully for servers, and — by decoupling the surface from preemption — is the one way to get Active Oberon's ergonomics on wasm. If a grammar change is *not* wanted, fall back to Option 1's library `Spawn`/`Chan`, optionally still offering `AWAIT` as a scheduler primitive.

## 5. Recommendation

Adopt a **shared surface with per-backend schedulers** (§2.1). The **wasm/LLVM** scheduler is **cooperative stackful single-thread** — the *smallest* runtime that gives an easy, blocking-style API, removing races by construction; its one cost is the wasm stack-swap, which JSPI makes clean (fallback: Asyncify — DDR-016). The **816/OS16** scheduler preempts **processes** (DDR-018): its kernel preempts processes for robustness/isolation, and the Verilog core's relocatable stack/DP make it cheap — so the 816 is *not* held to the cooperative model *at the process level*. Per DDR-018 §5.1 in-process tasks are cooperative on every backend, so `{EXCLUSIVE}` is free within a process everywhere and `AWAIT` is the portable condition primitive. **Option 4's raw handler** stays as an escape hatch; **Option 5 (multi-core parallelism) is deferred**. Choose Option 2 (stackless async) for the *cooperative* backends only if **wasm without JSPI/Asyncify is a hard requirement**; the price is a large, colouring compiler transform, and it does not affect the 816.

**The surface fork is decided (2026-08-03): Option 1 — library `Spawn`/`Chan`.**

A `Tasks` module (`Spawn`, `Yield`) plus a `Chan` interface; **no grammar change**. A task is a procedure or an object method; a condition-wait is `WHILE ~cond DO Tasks.Yield END`; values move between tasks over a `Chan`.

*Rationale.* The cooperative-in-process decision (DDR-018 §5.1) makes Active Oberon's two distinctive features **dormant**: `{EXCLUSIVE}` is free (no in-process preemption; processes are isolated) and `AWAIT(cond)` is equivalent to a yield-loop under cooperative scheduling. Adding the Active Oberon *grammar* now would introduce keywords whose signature semantics do no work — against the minimalism that is the parent OO record's core value. The library gives the whole cooperative I/O model with zero grammar cost.

*Rejected: Option 6 (Active Oberon `{ACTIVE}`/`{EXCLUSIVE}`/`AWAIT` grammar).* Attractive as the capstone of the OO work and faithful to the in-family lineage, but its monitor/condition machinery is not load-bearing under the chosen cooperative model. **It remains the documented upgrade path:** if in-process preemption (DDR-018 §5.1 rejected alternative) or multi-core parallelism (§4 Option 5) is ever adopted, `{EXCLUSIVE}`/`AWAIT` become real and the grammar earns its keep — and library `Spawn`/`Chan` code coexists with it, so the promotion is non-breaking. The hybrid (`{ACTIVE}` object bodies + library `Chan`) is the natural first step of that promotion if only the spawn ergonomics are later wanted.

*Other open sub-decisions, independent of the surface fork:*
- **Channel typing.** Channels of a concrete element type need the narrow-generics decision (parent §3) or an interface-typed (boxed) channel. Recommendation: interface-typed `Chan` to start; revisit with typed collections.
- **Cancellation / deadlines.** Tasks/activities that block on I/O already carry DDR-010 deadlines; add a `Cancel` on the task/object handle. Recommendation: include from day one — servers need it.

## 6. Consequences

1. **Servers become straight-line code:** an accept loop `Spawn`s a handler per connection; each handler reads/writes its `Conn` with blocking-looking calls. This is the shape DDR-015/017 assume.
2. **No language memory model, no user-visible locks** — deferred with parallelism (Option 5). The library stays lock-free because scheduling is cooperative.
3. **DDR-011 must expose non-blocking I/O readiness** (`poll`/`select`/`epoll`/`kqueue`; the browser event loop). Add this to its primitive list (§7).
4. **The GC/ARC must be task-aware** only to the extent of scanning each task's stack (stackful) — a known, bounded addition. Stackless (Option 2) would instead make frames heap records.
5. **wasm** rides on JSPI/Asyncify (DDR-016) under Option 1, or is native under Option 2.

## 7. Amendments this record proposes to prior records

- **DDR-011 §3 →** add I/O-readiness primitives (`poll`/wait-for-ready; browser event-loop hook) and, if Option 5 is ever taken, a thread-spawn primitive (native only).
- **DDR-010 →** no change; its deadlines are the cancellation substrate.
- **Parent OO §3 "Closures" →** a `Spawn(P)` that captures state wants closures; this record raises the priority of that open item (see DDR-013 §6).

## 8. As-built — `Tasks`, first cut (LLVM/POSIX)

`runtime/posix/Tasks.Mod` + `Tasks_rt.c`, a cooperative stackful scheduler on one OS thread (Option 1). The surface is deliberately tiny:

```
  Task = INTERFACE PROCEDURE Run () END;   (* a stateful task: an object *)
  PROCEDURE Spawn (b: PROCEDURE);          (* a parameterless task *)
  PROCEDURE SpawnTask (t: Task);           (* an object task — carries state *)
  PROCEDURE Yield ();                       (* cooperative reschedule *)
  PROCEDURE Run ();                         (* drive all tasks to completion *)
```

- **Closures via objects.** Oberon has no closures (DDR-013 §6), so a task that needs captured state (a connection handler needs its `Conn`) is an **object** implementing `Task`; `Spawn(proc)` is just the object adapter over a bare procedure. This is the whole answer to "`Spawn(P)` wants closures" — the object *is* the closure.
- **Division of labour.** C owns the stacks (`ucontext`), the run queue and the `poll` set; Oberon owns the task objects and dispatch. The fat interface pointer never crosses into C — the scheduler calls one Oberon entry, `Tasks.taskMain(id)`, which invokes `taskList[id].Run()`. This keeps the C side ignorant of the interface ABI.
- **Blocking-looking I/O yields transparently.** Sockets are non-blocking; on `EAGAIN` the `Net` C bridge calls a runtime seam `oc_iowait(fd, want)`, which the scheduler installs a hook into (via a constructor) to **park the current task** and let others run until `fd` is ready. **With no scheduler running** (`Tasks.Run` not entered, or `Tasks` not linked) `oc_iowait` falls back to a **blocking `poll`** — so the same `Net` code is straight-line-blocking for a simple client and cooperatively-scheduled inside `Tasks.Run`, with no API split and no `async` colouring. This is the DDR-011 §3 I/O-readiness primitive, realised.
- **`Net.Serve` is now the concurrent accept loop.** It accepts, `SpawnTask`s an echo/handler object per connection, and loops; `Accept` yields while it waits. Verified by `tests/ConcTest.Mod`: a server task and three client tasks on one thread — all three connections are open simultaneously (the clients all reach their blocked `Read` before any echo returns), which a serial server could not produce.

**Deferred from this cut:** `Chan` (blocked on channel element typing — parent §3 narrow-generics; the spawn-per-connection server doesn't need it), a `Cancel`/deadline handle (§5), and the wasm/816 schedulers (this is the LLVM/POSIX one only, per §2.1). The `Net`→`Tasks` import means the ~200-line scheduler links into every `Net` program, but it is dormant (identical blocking behaviour) until `Tasks.Run` is called.
