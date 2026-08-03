# Design Decision Record 011: The Platform (Syscall) Layer as Shared Runtime Interface

**Author:** Jason Swain
**Date:** 2026-07-14
**Status:** Accepted (architecture); the concrete primitive list (§3) is expected to grow as libraries are implemented.
**Relationship to prior records:** Standalone sibling to DDRs 001–010. It specifies the low-level layer that the DDR-009/010 library *implementations* bottom out into, and answers whether that same layer can serve as the compilers' runtime interface. Prior documents are not modified.

---

## 1. Context

DDR-009 and DDR-010 define portable library interfaces (`Conn`, `File`, `FileSystem`, `Directory`, `Clock`) whose implementations differ per backend: libc/POSIX on the hosted/LLVM target, kernel syscalls on OS16. Separately, every compiled program needs a **runtime**: the layer between compiled code and the OS, including at minimum the allocator/GC (DDR-001 assumes a GC), process start-up, and exit. On the hosted backend the runtime would otherwise call libc directly from scattered sites.

Two questions are settled here: (1) what the primitive OS-operation layer beneath the standard library is, and (2) whether that same layer should also *be* the compilers' runtime interface rather than a separate mechanism.

---

## 2. Decision

### 2.1 One platform layer, consumed by both the standard library and the runtime
**Status:** Accepted

Define a **single platform (syscall) layer**: the complete set of primitive OS operations the whole system needs — I/O, time, memory, and process control. It is the sole OS-abstraction seam. **Both** the standard library (DDR-009/010) **and** the language runtime (allocator/GC, start-up, exit) are *clients* of it. The runtime is not a separate OS-abstraction; it obtains memory and process services through the same layer, exactly as `File` obtains I/O through it.

This directly answers the motivating question: **yes, the syscall layer is reused as the compilers' runtime interface.** The GC asking the OS for pages is the same kind of call, through the same seam, as the file library asking to read bytes.

### 2.2 Link-time selection, not runtime dispatch
**Status:** Accepted

The platform layer is a **module with a fixed set of procedure signatures**, and the two backends provide two modules satisfying those signatures, chosen at **link time**. It is **not** a DDR-008 `INTERFACE` with runtime dispatch.

**Rationale.** There is exactly one OS per binary, selected when you build, so runtime polymorphism buys nothing and would cost a vtable indirection on the hottest path in the system (every syscall, every allocation). Oberon's module system already gives link-time swapping for free: one `Platform` definition, two implementation modules, link the matching one — direct calls, zero dispatch overhead. This is the correct division of labour with DDR-008: runtime-dispatched interfaces live at the *library* level where composability is wanted (real FS vs zip FS, TLS vs plain `Conn`); link-time module selection lives at the *platform* level where there is one implementation per build and overhead must be zero.

### 2.3 Source-level interface vs machine ABI
**Status:** Accepted

The platform layer is defined at the **Oberon-procedure level** (typed procedures in a module). How those procedures *lower* is backend-specific and below the interface:
- **OS16:** each lowers to a numbered kernel **trap** with a register calling convention (syscall number + register args).
- **Hosted/LLVM:** each lowers to a **libc call** (or, if a libc-free binary is ever wanted, a raw Linux syscall in the Go manner).

The library and runtime see typed procedures; the trap-number/register ABI is an OS16 lowering detail, and the libc mapping is a hosted lowering detail.

---

## 3. The primitive set

Enumerating what DDR-009/010 need *defines OS16's I/O syscall ABI*. The minimal set reads straight off the interfaces, plus the memory and process primitives the runtime adds:

**I/O and filesystem**
`open(path, flags, mode) → handle`, `read(h, buf, n) → count`, `write(h, buf, n) → count`, `close(h)`, `seek(h, off, whence) → pos`, `fstat(h) → info`, `readdir(h) → entry`, `mkdir(path, mode)`, `unlink(path)`, `rename(old, new)`

**Sockets**
`socket(domain, type) → handle`, `bind`, `listen`, `accept → handle`, `connect`, `setopt` (deadlines ride on `setopt`)

**Time**
`clock(id) → nanos` (id selects wall vs monotonic — the two `Clock` readings from DDR-010 §2.6)

**Memory** (runtime client, not surfaced in the stdlib)
`mapPages(n) → addr`, `unmapPages(addr, n)` — the GC/allocator's window onto the OS

**Process**
`exit(code)`, and start-up entry (argument/environment access as needed)

This list is the contract between the OS16 implementation module and the kernel, and simultaneously the checklist for the hosted module's libc shim.

---

## 4. Why reuse pays (consequences)

1. **One portability seam.** The entire OS dependency of the whole system — stdlib *and* runtime — is this one module. Everything above is written once.
2. **Bootstrap and test OS16 userland on the hosted backend first.** Because the runtime and the whole standard library sit on the platform layer, running the hosted implementation of that layer lets the entire OS16 userland (libraries, and code written against them) be developed and tested on an existing OS *before the OS16 kernel exists*. Swapping in the kernel-backed platform module is then the final step, not a prerequisite. This is a large development-velocity win.
3. **Proven precedent.** This mirrors Go's per-`GOOS` syscall layer (raw syscalls on Linux, libc calls on Darwin — a single internal surface, implemented per platform) and WASI (a small syscall-like interface — `fd_read`, `path_open`, `clock_time_get`, memory growth — implemented by whatever host runs the module). The primitive set in §3 maps almost one-to-one onto WASI preview1, which is independent evidence the layer is factored at the right granularity.
4. **The runtime stops calling libc ad hoc.** On the hosted backend, all libc contact is funnelled through the platform module rather than scattered across the runtime and stdlib, so the libc dependency is one auditable boundary.

---

## 5. Caveats (accepted, with open sub-points)

1. **Memory is the hard part of the abstraction.** I/O is naturally handle-based and uniform across hosted and bare-metal; memory management is not. On the hosted target, memory arrives as an mmap'd region the host OS manages; on OS16 you control physical pages directly. The `mapPages`/`unmapPages` shape must be abstract enough to cover both without leaking either model — this is the one primitive worth designing carefully rather than by analogy to POSIX. **Open sub-decision:** the exact page-allocation contract.
2. **libc is itself a runtime.** Going through libc on the hosted target layers our runtime on libc's (its `malloc`, buffering, `errno`, signal handling). This is the pragmatic choice for the hosted backend, whose purpose *is* to run on an existing OS; a raw-syscall, libc-free hosted backend (Go's Linux choice) is possible but only warranted if libc-free hosted binaries are ever a goal. On OS16 the question does not arise — there *is* no libc; the platform module is the bottom of the stack and you own it. So the two implementations naturally differ in whether a C library sits beneath them.

---

## 6. Blocking dependencies

None new. This record is downstream of the DDR-009/010 interfaces (which determine most of §3) and of DDR-001 (the GC that consumes the memory primitives). It does not block the *interface* design of the standard library — those are decided — but it is the prerequisite for *implementing* the library on either backend.
