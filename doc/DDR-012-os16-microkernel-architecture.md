# Design Decision Record 012: OS16 Microkernel Architecture and Kernel Primitive Interface

**Author:** Jason Swain
**Date:** 2026-07-14
**Status:** Accepted (baseline architecture). Three residual items are open (§5) and are recordable rather than blocking; two capabilities are deferred and hardware-gated (§6).
**Baseline scope:** uniprocessor; MMU *enforcement* deferred; single-user, low/no security. These are the assumptions the design is optimised for, with later capability deliberately designed-in.
**Relationship to prior records:** Standalone sibling to DDRs 001–011. It specifies the kernel that sits *beneath* the servers which implement the DDR-011 platform layer: on OS16, the DDR-011 platform surface lowers to server IPC, and the kernel exposes only the primitives in §3. Hardware-platform specifics (soft-core, cache) are referenced only where they touch the kernel interface (§4); a separate hardware record can capture them in full. Prior documents are not modified; §7 lists the amendments they would receive.

---

## 1. Context

OS16 is a microkernel for the custom target (a modified 65C816 soft-core on FPGA, with a cache). DDR-011 established a single platform layer consumed by both the standard library and the language runtime. This record defines the kernel below the servers that back that layer, and fixes the OS structure: what runs in the kernel, what runs as a user-space server, and how they communicate. It also records how the DMA/cache-coherency concern (a uniprocessor issue, not only an SMP one) enters the kernel's DMA primitives.

---

## 2. Decisions

### 2.1 Microkernel with active-object servers
**Status:** Accepted

The kernel is minimal; OS services — filesystem, networking, device drivers, the name registry — are **user-space servers**. Each server is an **active object**: a single thread that owns its state and processes a serialized message queue, so its state needs no locks.

**Rationale.** The alternative (a library-server, where the caller's own thread enters the server and runs its code over shared module state) collides with preemptive multitasking (§2.4): two preempted threads in the same server race its globals and force locking. The active-object model serializes by construction and, as a bonus, is already SMP-shaped — a server that never shares state is correct on one core or many — which is why it also makes the SMP deferral (§6) clean.

### 2.2 Invocation model — modules lower to messages
**Status:** Accepted

The Oberon **module import + exported procedure call** is the invocation interface everywhere (continuing the DDR-005 static-binding lineage and the DDR-011 §2.3 source-interface-vs-lowering split). How it lowers depends on the boundary crossed:
- **Same address space:** a direct procedure call.
- **Across servers (and under any future address-space isolation):** a **copy-message** send to the target server's queue.

**Forward-compatibility guarantee.** Because every server-facing procedure already carries a `VAR err: Error` (DDR-010 §2.1), a transport failure — "server gone", queue full, future cross-space fault — already has a channel to report through. This is precisely what lets "modules *are* IPC" survive the later introduction of address-space separation **without changing a single server signature**. Had these calls been infallible, isolation would be un-retrofittable.

### 2.3 Message passing by copy
**Status:** Accepted

Control messages are passed **by copy**, so no memory is shared between client and server. This makes the entire IPC path **MMU-agnostic**: protection becomes pure enforcement, never a correctness prerequisite, which is what removes the MMU from the critical path.

Bulk data (framebuffer, block and network buffers) is handled by **explicitly mapped/granted regions**, not per-message copy — a special-cased use of the map-into-space primitive (§3), not the common path.

### 2.4 Preemptive multitasking; the scheduler is in the kernel
**Status:** Accepted

Scheduling is preemptive (required for networking: a blocked socket read must not stall the machine). The **scheduler cannot be a server** — the mechanism that preempts must sit below the threads it preempts — so it is kernel code, driven by a **kernel-owned periodic timer interrupt** for the scheduling quantum. This timer tick is distinct from the receive-with-timeout wakeups that IPC provides (§3).

### 2.5 Capability shape now, enforcement later
**Status:** Accepted

Every kernel-issued reference (to a handle, port, address space, device region) is an **opaque, unforgeable token from day one** — never a raw guessable integer index. Rights-checking on those tokens is deferred (single-user, low/no security initially) and, because the tokens are already opaque, becomes a purely **internal** kernel change later with no caller-visible signature change.

**Rationale.** Whether primitives carry capabilities is signature-shaping and cannot be cheaply retrofitted; *what the policy is* can be. Raw integer indices would bake in ambient authority and make capabilities a re-plumbing job. This is the one security-adjacent decision that must be made at the start even though the security work is deferred.

### 2.6 Driver model — stream vs block
**Status:** Accepted

- **Stream drivers** (serial/UART) reuse `Reader`/`Writer` (DDR-009) — no new interface; a UART *is* a byte stream.
- **Block drivers** get a distinct interface (read/write by logical block address, flush, capacity/geometry query); the filesystem server layers on top of it.
- Drivers are **user-space servers**. The kernel owes a driver only: interrupt delivery, device-memory mapping, and DMA-capable buffer allocation (§3). Nothing device-specific lives in the kernel.

### 2.7 DMA and cache maintenance (a uniprocessor concern)
**Status:** Accepted

DMA is a second bus master, so it creates a cache-coherency problem **on a uniprocessor**, in both directions: inbound (device→memory) leaves stale cache lines that must be **invalidated**; outbound (memory→device) may leave dirty lines in a write-back cache that must be **cleaned** before the transfer.

Policy:
- **Default — uncached staging buffers.** A buffer region marked non-cacheable (per-page via the software-managed TLB once the MMU exists; a fixed uncached SDRAM alias window before then) needs no maintenance ever. Simplest; slow CPU access, fine for hand-off staging.
- **Throughput path — line-aligned software maintenance.** Invalidate/clean by range at the submit/complete boundaries. Correctness is guaranteed *for free* by the async buffer-ownership contract already in the design (buffer untouchable between submit and completion), so a single clean at submit or invalidate at completion suffices — no per-access work.
- The **DMA-capable allocator** (already in the design) gains **cache-line alignment and line-length padding**, so a buffer never shares a line with unrelated CPU data (which would turn an invalidate into a corruptor of its neighbour).
- **Instruction-cache invalidation on program load** is a named instance: after block-DMAing an executable in, invalidate the I-cache (and clean the D-cache) over the region before jumping to it. With oldland's separate I/D caches this is a distinct step.
- Hardware **snoop coherency** is parked with SMP (§6) — it is the same machinery.

### 2.8 Graphics, formatting, and other devices
**Status:** Accepted

- **Graphics:** assuming a linear framebuffer, the kernel's entire involvement is mapping the framebuffer's physical memory into the display server. All drawing, compositing, windowing, and fonts are userland library/server work.
- **Filesystem creation ("formatting"):** pure userland over the block interface — no kernel involvement.
- **Keyboard/mouse:** input-driver servers built on interrupt delivery + register access; an input server multiplexes events to applications over IPC.

---

## 3. Kernel primitive set

The complete kernel surface. Everything else is a server or library above it.

**IPC**
- `send` / `receive` (copy-message), with **receive-with-timeout** — which subsumes blocking, rendezvous synchronisation, and sleep from one mechanism (the L4 lesson), so no separate sleep/mutex/timer-wait primitives are needed.

**Threads and address spaces**
- thread create / destroy
- address-space (process) create
- `map` / `grant` pages **into a space** (generalising DDR-011's `mapPages`; the by-copy IPC model means this is used mainly for bulk-data regions, not control transfer)

**Handles**
- opaque-handle issuance (§2.5)

**Devices**
- interrupt registration / delivery (turn a hardware IRQ into a message or a wakeup for a driver thread)
- device-memory mapping (map a physical MMIO region, caching disabled, into a driver's space; plus I/O-port access if the hardware has a separate port space)
- DMA-capable buffer allocation (contiguous, pinned, cache-line-aligned per §2.7)

**Time / scheduling**
- scheduler with its periodic timer tick (§2.4)

**System**
- `exit` / power control (shutdown, reboot)
- early debug-console primitive (for bring-up before any driver server exists)
- entropy source (minor now; a hard dependency once the deferred security work begins)

---

## 4. Hardware context (referenced; detailed in a separate record)

- **Uniprocessor baseline** on a modified 65C816 soft-core (movable direct page and stack, enabling per-address-space layout) with a cache (oldland/Keynsham-derived).
- **MMU deferred but designable.** The '816 **ABORT** input provides the abort-and-restart hook a demand-paging MMU needs; oldland's **software-managed TLB** (4KB pages, separate I/D, software miss handlers) means the OS owns the page-table format — a clean fit for the microkernel-owns-policy stance. The cache may be grafted **without** the TLB, keeping the MMU off the critical path per §2.3.
- **Atomics already exist in the ISA.** The '816's RMW instructions plus the ML (Memory Lock) pin give hardware-backed atomic bus cycles (`TSB` is effectively a test-and-set). On the uniprocessor baseline atomicity against interrupts is automatic; ML matters only under multi-master/multi-core.
- **SMP deferred; its sole hard prerequisite is a cache-coherency protocol.** oldland's caches have none, so multicore = building coherency (and reconciling ML-style atomics with it via cache-line ownership rather than a bus lock). This is the true cost of SMP, not core replication.

---

## 5. Open decisions (resolve with implementation)

1. **Server registration / name registry.** Modules-as-IPC (§2.2) fixes the *model* — an import resolves to a server. The residual mechanism is how a server publishes itself and how the loader binds an import to it (a direct link under shared space; a registry-issued port/capability under isolation). The registry is itself a user-space server.
2. **IPC message primitive shape.** Synchronous rendezvous vs asynchronous queue; message size/format and any bound; whether receive-with-timeout is the sole blocking primitive. §2 fixes the *model* (copy, active-object queue); this fixes the *primitive*.
3. **Cache write policy (write-through vs write-back).** A read of the oldland RTL, not a design choice — it determines whether the outbound-DMA clean path (§2.7) is needed at all.

---

## 6. Deferred (non-breaking, hardware-gated)

- **MMU enforcement** — designed-in via the ABORT hook and software-managed TLB (§4); added later with no server-interface change because IPC is by-copy (§2.3).
- **SMP** — gated solely on a cache-coherency protocol (§4); the active-object model (§2.1) means server *interfaces* are already ready.
- **Hardware snoop DMA coherency** — the same coherency machinery as SMP (§2.7); until then, software maintenance or uncached buffers.

---

## 7. Amendments this record makes to prior DDRs

- **DDR-011:** on OS16, the platform layer lowers to **active-object server IPC**, and the kernel exposes only §3's primitives; the `send`/`receive`-with-timeout primitive is the transport those lowerings use. The memory primitives (`mapPages`/`unmapPages`) generalise to map/grant-into-a-space (§3).
- **No change** to DDRs 001–010. This record depends on DDR-001 (GC/allocator as a platform-layer client), DDR-005 (static-binding invocation lineage), DDR-009 (`Reader`/`Writer` for stream drivers), DDR-010 §2.1 (the `VAR err` channel that makes modules-as-IPC isolation-ready), and DDR-011 (the platform layer this kernel sits beneath).
