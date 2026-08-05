# Design Decision Record 018: 65C816 Hardware Profile (Verilog Core), Memory Model, and Two-Level Scheduling

**Author:** Jason Swain
**Date:** 2026-08-03
**Status:** **Accepted.** §2 hardware relaxations are built into the core; §3 DP/stack bank selector resolved to **Option A (DPR)** (2026-08-03); §5.1 in-process tasks resolved to **cooperative** (processes remain preemptive) (2026-08-03).
**Scope:** **65C816 target only.** Per DDR-014 §2.1 the LLVM/wasm backends are deliberately *not* constrained by anything here, and nothing here is constrained by them.
**Relationship to prior records:** This is the hardware record DDR-012 anticipated ("a separate hardware record can capture them in full"). It refines the memory constraints DDR-013 §4 (816 ABI) and DDR-014 assumed, and it is the substrate for DDR-012's kernel and DDR-014's 816 (preemptive) scheduler.

---

## 1. Context

The design so far assumed a **stock** 65C816, whose two hard limits shaped everything:

- the hardware **stack is bank-0-only** (SP is 16-bit; the stack's bank byte is fixed at `$00`), so *every* task and *every* process shares one 64 KB bank for stacks — a hard cap of "tens of tasks" and no stack isolation;
- the **direct page** (the compiler's register file, `D+$00…$47`) is likewise confined to bank 0.

The target is now a **custom Verilog 65C816 core** that relaxes both. This changes the concurrency and isolation arithmetic enough that it must be recorded before DDR-012/014 are built against the old assumptions.

## 2. Hardware relaxations (decided — built into the core)

1. **Full 16-bit data bus.** A 16-bit access is one bus cycle, not two. Pure performance; **no ISA or compiler change** — existing `.816` code runs faster unmodified.
2. **16-bit page-granular DPR.** The Direct Page Register is a 16-bit **page number**: DP base = `DPR << 8`, page-aligned anywhere in the 24-bit (16 MB) space. The per-task register file (`D+$02…$1E`, SB at `D+$00`, `BANK_DP` at `D+$44`) can now live in **any bank**. *DP leaves the bank-0 jail.*
3. **Relocatable stack.** The stack's 24-bit address is `DPR.high : SP16` — the stack bank is the DPR's high byte, co-locating stack and DP in the DPR-selected bank. *The stack leaves the bank-0 jail.*

Net: **DP + stack are per-context and can sit anywhere in memory**, selected by one register (DPR).

## 3. Open option — what selects the DP/stack bank

The author has built (2) + (3) with the **DPR** as the selector, and is weighing whether the **DBR** would be more elegant.

- **Option A — DPR high byte selects the DP/stack bank (as built).** The DPR is stable across a routine and changes only on a deliberate context switch, so the stack never moves unexpectedly. Decoupled from data addressing. **Recommended.**
- **Option B — DBR selects the DP/stack bank.** Appealingly, one register would then be "the task's whole memory home" (data + DP + stack). But **`DBR` is the volatile register** — it is what code changes to reach another bank's data (`PHB/PLB`, per-access bank switches, interrupt handlers, hand-written assembly). Tying the stack to `DBR` means **any cross-bank data access relocates the live stack** — a catastrophic, non-local failure. Safe *only* if the compiler and all hand code are *guaranteed* never to mutate `DBR` while a stack is live (e.g. all cross-bank data via long/24-bit addressing). **Not recommended** at that fragility.
- **Option C — a dedicated stack/DP bank register (`SBR`).** The safe version of B's single-register elegance: a register used for nothing but the DP/stack bank, independent of the volatile `DBR`. Costs a little hardware. **Recommended only if the single-register model is wanted** — otherwise A already achieves it economically.

**Decision (2026-08-03): Option A — the DPR high byte selects the DP/stack bank, as built.** The stack stays tied to the register that only changes on a deliberate context switch, decoupled from the volatile `DBR`. B is rejected (stack-relocation hazard); C is not pursued (A already gives the placement freedom economically).

## 4. Memory model consequence

With DP + stack relocatable, the address space partitions cleanly by **bank**:

- **Processes** get their own bank(s) for code / data / DP / stack → **isolation by layout**. This is *soft* isolation (no MMU enforcement yet — a rogue `DBR` or long-store can still escape), but the layout is genuinely separated and **upgrades to hard** the day the core adds an out-of-range trap, with no change to the software model. Matches DDR-012's "MMU enforcement deferred, hardware-gated."
- **Tasks** (lightweight, in-process) are a **DP page + a stack sub-range within a process's bank** — many per bank.
- **Concurrency scales to ~hundreds** (up to 256 banks; lightweight tasks pack several per bank), versus the stock core's "tens" bank-0 bound.
- **Preemptive context switch stays cheap:** reload `DPR` (which swaps the entire DP-relative register file in one write) + `SP` + `DBR` + the CPU regs (`A/X/Y/P` via the IRQ). ~50–70 cycles.

## 5. Two-level scheduling (the "two mechanisms")

The hardware makes the natural OS structure a **two-level (M:N) scheduler**:

| | Processes (heavy) | In-process tasks (light) |
|---|---|---|
| Owner | DDR-012 kernel | DDR-014 runtime |
| Scheduling | **preemptive** (timer IRQ) — always, for robustness/isolation | preemptive **or** cooperative (open, §5.1) |
| Memory | own bank(s); layout-isolated | DP page + stack region within a process bank |
| Mutual exclusion | processes share no mutable state | `{EXCLUSIVE}` (real if preemptive; free if cooperative) |

Preemption at the **process** boundary is non-negotiable (a runaway process must not hang the machine) and is now comfortable because each process is a self-contained set of banks. The **critical seam** (DDR-014 §6): a task that makes a *blocking* kernel call blocks its whole process, starving sibling tasks — so the kernel must expose **non-blocking I/O + readiness** (DDR-011) and the runtime multiplexes on it.

### 5.1 In-process tasks are cooperative (decided 2026-08-03)

**Decision: cooperative in-process tasks; preemption stops at the process boundary.** Only processes are preempted (by the kernel, for robustness and isolation); within a process, active objects / tasks yield at I/O and `AWAIT`. Consequences:

- `{EXCLUSIVE}` within a process is **free** (a region simply never yields), and there are **no intra-process data races** — no intra-process memory model needed.
- The in-process programming model is **identical to wasm/LLVM** (both cooperative), so a program's task logic behaves the same on every backend; only the process/kernel layer, which wasm lacks, differs.
- A CPU-bound task can still be bounded without true preemption by a "please-yield" timer flag checked at safe points (DDR-014 §6), preserving cooperative memory semantics.

The rejected alternative — **preemptive in-process tasks** (full Active Oberon, kernel time-slicing active objects) — was available (the relocatable per-task stacks make it cheap) but reintroduces intra-process races that `{EXCLUSIVE}` would have to cover, for fairness inside a process that this workload does not need. It can be revisited if a future CPU-bound in-process workload demands it, without changing the surface.

## 6. Consequences

1. **DDR-014's bank-0 concurrency bound is removed** for the 816; per-task/per-process stacks are first-class.
2. **DDR-012 gains a concrete process memory layout** (bank-per-process) and a cheap preemptive switch built on relocatable DPR/stack.
3. **Soft isolation now, hard-if-trap later** — the process abstraction is in place, so adding hardware enforcement is a core change, not a software redesign.
4. **LLVM/wasm are untouched** (DDR-014 §2.1): none of §2–§5 applies to them.

## 7. Amendments this record proposes to prior records

- **DDR-012 →** replace the stock-816 memory assumptions with §2/§4; adopt the bank-per-process layout and the two-level scheduler (§5); note the DP/stack bank-selector open option (§3).
- **DDR-013 §4 →** note that on the Verilog core the 816's DP and stack are relocatable (per-context), not bank-0-fixed; the ABI (register file at `D+…`) is unchanged, only its *location* is now free.
- **DDR-014 →** the 816 (preemptive) scheduler and its "not constrained by wasm" principle (§2.1) are realized here; the bank-0 bound is lifted.
