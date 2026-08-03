# Design Decision Record 016: Platform Network Backends (POSIX, Apple, Android, wasm)

**Author:** Jason Swain
**Date:** 2026-07-28
**Status:** **Draft — options open.** Native backends are near-mechanical; **wasm is the real decision** and is where the options live (§3). Author decides §3.1/§3.2/§4.
**Relationship to prior records:** Implements the `Net` module of **DDR-015** on each runtime by providing the **DDR-011** primitives (or a substitute where they cannot exist). Feeds I/O readiness to the **DDR-014** scheduler. No prior *decisions* change; this records how each backend satisfies the portable surface.

---

## 1. Context

DDR-015's `Net` is portable; its floor is per-runtime. On the native runtimes the DDR-011 primitives *are* BSD sockets and the backend is thin. In the browser they **cannot exist**: wasm/JS has no raw TCP by design (security), no `connect()` to an arbitrary host:port. So "defer the work to the OS" is true on native and *false* on wasm, where the only transports are the ones the browser exposes. That asymmetry is the whole content of this record.

## 2. Native backends (POSIX / macOS, iOS, Android)

All three are POSIX-socket platforms; the DDR-011 primitives map 1:1:

| DDR-011 primitive | native call |
|---|---|
| `socket`,`bind`,`listen`,`accept`,`connect` | BSD sockets |
| `setopt` (deadlines) | `setsockopt` `SO_RCVTIMEO`/`SO_SNDTIMEO`, or non-blocking + `poll` |
| I/O readiness (DDR-014) | `kqueue` (macOS/iOS), `epoll` (Android/Linux), `poll` (portable floor) |

Per-platform notes, none of which touch the `Net` surface:
- **macOS/POSIX:** the reference backend; non-blocking sockets + `kqueue` drive the DDR-014 scheduler.
- **iOS:** same BSD sockets; add the Info.plist entitlements (local-network permission) and, if backgrounded sync is wanted, a background-task assertion. A future refinement could lower to `Network.framework` (`nw_connection_t`) for system-managed connectivity, but BSD sockets work today and keep the backend uniform. *Open, minor.*
- **Android:** BSD sockets via the NDK; `INTERNET` permission in the manifest; `epoll`. Cleartext-traffic policy applies (pushes toward TLS or an explicit exception).

**Verdict:** native backends are a mechanical DDR-011 implementation shared across the three POSIX targets, differing only in the readiness syscall and platform permission boilerplate. Low risk; not the decision.

## 3. wasm backend — the actual decision

The browser offers no raw sockets. The realistic transports:

- **WebSocket** (`ws://`/`wss://`) — a persistent, **bidirectional, ordered, reliable, message-framed** stream. This is the closest thing to a TCP `Conn` a browser has, and it maps cleanly onto `ReadWriteCloser` (message stream → byte stream; the WS layer owns framing). The catch: it is **not** raw TCP — the *server* must speak the WebSocket handshake + framing. Since we own the server (it's our Oberon server, DDR-017), that is acceptable and even desirable.
- **fetch / HTTP** — request/response only; no persistent bidirectional channel. Fine for "GET a file," not for streaming/push sync. Could fake a channel with long-poll, but poorly.
- **WebTransport** (HTTP/3 / QUIC) — bidirectional streams *and* datagrams, the modern answer; but needs an HTTP/3 server and is still stabilising across browsers. More power than the sync case needs.
- **Relay / proxy** — a native side-car (websockify-style) that bridges browser WebSocket ↔ raw TCP to an unmodified TCP server. Avoids changing the server but adds an always-on piece of infrastructure and a second hop.

### 3.1 Which transport for wasm — decision

- **Option A — WebSocket, and the Oberon server speaks WebSocket.** *Recommended.* The wasm client dials `wss://host/sync`; the server's `Net` also offers a `"ws"` listener; the connection is a `Conn` on both ends. One protocol we control end-to-end, TLS for free (`wss` is browser-terminated), no side-car.
- **Option B — WebSocket via a relay to a plain-TCP server.** Keeps the server transport-ignorant but adds infrastructure and a hop. Choose only if the server must also serve non-WebSocket TCP clients that can't be changed.
- **Option C — fetch-only, request/response sync.** Simplest to reach first (no persistent connection, no server WS), but gives up push/streaming and doesn't reuse the `Conn` model. Viable as a *degenerate v0* for pure "read a file," not for two-way sync.
- **Option D — WebTransport.** Defer; revisit if datagrams or multiplexed streams are ever wanted.

### 3.2 Transport uniformity — do native clients also use WebSocket?

Follows from 3.1-A. Two sub-options:

- **Uniform: everything is WebSocket.** Native clients dial `ws://` too; the server has a single listener. Cost: a **WebSocket implementation on native** (handshake + framing over TCP — a few hundred lines of *reusable Oberon*, which suits the "server in Oberon" goal and gives the native client the exact same wire protocol as the browser). *Recommended* — one wire format, tested once, and the WS layer is itself a `Conn`-wrapping-`Conn` (like TLS in DDR-015 §3.4).
- **Dual: native uses raw TCP, wasm uses WebSocket.** The server listens on both; two wire formats to test. Slightly faster on native (no WS framing), but two code paths for no real benefit at sync data rates. *Not recommended* unless a measured throughput need appears.

### 3.3 wasm concurrency mechanism (feeds DDR-014)

DDR-014 Option 1 (stackful green tasks) needs a stack swap, which wasm's protected call stack forbids from user code. Two ways to get it:

- **JSPI (JS Promise Integration)** — native browser stack switching for wasm; a blocked task suspends to a JS Promise and resumes on the WebSocket `message`/`open` event. *Recommended* — it is the clean, now-shipping path, no whole-program transform, and it makes the blocking-looking API real in the browser.
- **Asyncify** (Binaryen) — a whole-program transform that unwinds/rewinds the wasm stack; works on every browser today but adds code size and per-call overhead. *Recommended fallback* while JSPI availability is gated.

Either way, the wasm backend's job is: drive the browser WebSocket, and on each `open`/`message`/`error`/`close` event, mark the waiting task ready and re-enter the DDR-014 scheduler. If DDR-014 instead chose Option 2 (stackless async), this section collapses — the state machines *are* the event loop and neither JSPI nor Asyncify is needed. So **§3.3 is contingent on the DDR-014 outcome.**

## 4. Recommendation (summary)

- **Native:** one shared BSD-sockets backend behind DDR-011; readiness via `kqueue`/`epoll`/`poll`; per-platform permission boilerplate only.
- **wasm:** **WebSocket** (3.1-A), server speaks it, **uniform WebSocket across native and browser** (3.2-uniform) via a reusable Oberon WS `Conn`-wrapper; TLS is free via `wss`. Concurrency via **JSPI** with **Asyncify** fallback (3.3), unless DDR-014 picks stackless async.
- **fetch-only (3.1-C)** is kept as an acceptable *read-only v0* if a persistent connection isn't ready.

## 5. Consequences

1. The **wire protocol is WebSocket-framed end to end** — the DDR-017 sync protocol rides inside WebSocket messages (or a byte stream over them), identical on browser and native.
2. The one genuinely new component is a **native WebSocket `Conn`** (handshake + RFC-6455 framing over a TCP `Conn`) — reusable Oberon, and structurally the same "wrap a `Conn`, expose a `Conn`" pattern as TLS.
3. wasm's viability hinges on **JSPI/Asyncify** *iff* DDR-014 is stackful; this couples the two records and is the main reason DDR-014 records the stackless option at all.
4. Native backends carry only permission/manifest boilerplate as per-platform difference — no `Net` surface divergence.

## 6. Amendments this record proposes to prior records

- **DDR-011 →** state explicitly that the socket primitives are **native-only**; the wasm platform provides a *transport object* (WebSocket) rather than the primitive set, so `Net`'s wasm backend is not a DDR-011 implementation but a sibling.
- **DDR-014 →** its wasm feasibility is realised here (JSPI/Asyncify); cross-reference.
- **DDR-015 →** the `"ws"` network string (DDR-015 §3.1-A) is the seam that makes this backend swap invisible to the app.
