# Design Decision Record 015: The `Net` Module — Dial, Listen, Serve

**Author:** Jason Swain
**Date:** 2026-07-28
**Status:** **Accepted; first cut implemented 2026-08-04 (LLVM/POSIX only).** The recommendations of §4 are taken: string `network`, opaque+printable `Addr`, `Serve` helper alongside raw `Accept`, TLS/UDP/deadlines deferred. `Streams`, `Net`, and `Net_rt.c` land in `runtime/posix`; a single-process loopback round-trip (`tests/NetTest.Mod`) exercises Listen/Dial/Accept/Read/Write/Close/RemoteAddr end to end. `Serve` is a **serial** accept loop until DDR-014 `Tasks` lands (§3.3). See §7 for as-built notes and the one open API question (no-length `Write`).
**Relationship to prior records:** Consumes **DDR-010** (`Conn`, `ReadWriteCloser`, `Addr`, deadlines) — this record does **not** redefine those; it produces them. Consumes **DDR-011** (socket/bind/listen/accept/connect primitives) and **DDR-014** (concurrency: the server shape). Its per-runtime backing — especially wasm — is **DDR-016**. Consumed by **DDR-017** (file sync).

---

## 1. Context

DDR-010 already settled the *value* you hold once you have a connection: `Conn` (a `ReadWriteCloser` with `LocalAddr`/`RemoteAddr`/read+write deadlines), interchangeable with a file wherever only the stream core is needed. DDR-011 already listed the platform primitives (`socket`, `bind`, `listen`, `accept`, `connect`, `setopt`). What is undesigned is the thin, portable **module** that ties them together:

- how a **client** obtains a `Conn` (connect to a host:port);
- how a **server** obtains a `Listener` and accepts `Conn`s;
- the **address** representation;
- the **high-level server helper** that makes writing a server "easy" (the stated goal), which is where DDR-014's `Spawn` shows up.

The design requirement from the brief: *easy to use and high level*, *defer work to the OS*, and *reusable for both client and server so the sync server can be written in Oberon too.*

## 2. Shape — two layers

Keep the raw seam and the ergonomic layer separate, in one module (or a `Net` + `Net.Server` pair):

```
  (* --- client --- *)
  PROCEDURE Dial(network, address: ARRAY OF CHAR; VAR err: Error): Conn;

  (* --- server, low level --- *)
  Listener = INTERFACE
    Closer;                                   (* from DDR-009/010 *)
    PROCEDURE Accept(VAR err: Error): Conn;
    PROCEDURE Addr(): Addr
  END;
  PROCEDURE Listen(network, address: ARRAY OF CHAR; VAR err: Error): Listener;

  (* --- server, high level (DDR-014 Option 1) --- *)
  Handler = INTERFACE PROCEDURE Serve(c: Conn) END;
  PROCEDURE Serve(l: Listener; h: Handler; VAR err: Error);
    (* accept loop; Spawn(h.Serve(conn)) per connection; returns on l.Close *)
```

`Conn`, `Addr`, `Error`, `Closer` are all imported from the DDR-009/010 core, so a socket, a file, and a TLS stream are the same `ReadWriteCloser` to every consumer — the whole point of DDR-010.

The **server is just:** `l := Listen("tcp", ":9000", err); Serve(l, myHandler, err)` — and `myHandler.Serve(c)` reads/writes `c` in blocking-looking straight-line code (DDR-014). That is the "easy, high level" target, and the same `Conn`/`Handler` code is reused by the client where a client also needs to answer the server (bidirectional sync).

## 3. Decisions to make

### 3.1 How is the network selected — string or typed?

- **Option A — string `network` ("tcp", "tcp4", "tcp6", "unix", "ws")** (Go style). Cheap, extensible (wasm adds `"ws"` without an API change), stringly-typed. *Recommended* — it lets DDR-016 add `"ws"`/`"webtransport"` for wasm with zero surface change.
- **Option B — typed `PROCEDURE DialTCP(...)`, `DialUnix(...)`.** Type-safe, but a new procedure per transport and no clean place for the wasm transports. *Not recommended.*

### 3.2 Address representation

DDR-010 named `Addr` but left it abstract. *Options:* (a) `Addr = INTERFACE PROCEDURE Str(): String; PROCEDURE Network(): String END` (opaque, printable — recommended, matches the interface style); (b) a concrete record `{host, port}` (leaks IP-ness, awkward for `unix`/`ws`). **Recommend (a)**, with a `ParseAddr`/`ResolveAddr(host, VAR err)` helper that DNS-resolves on native and is a no-op passthrough on wasm.

### 3.3 Server concurrency surface

This is where DDR-014 lands. *Options:*
- **A — `Serve(l, h)` helper** that owns the accept loop and `Spawn`s a task per connection (DDR-014 Option 1). Easiest; the recommended default.
- **B — expose only the raw `Accept` loop**; the app writes its own `Spawn`. More control, less "high level."
- **C — both:** `Serve` for the common case, `Accept` exposed for the uncommon. **Recommend C** — `Serve` is a ten-line wrapper over `Accept` + `Spawn`, so offering both costs nothing.

### 3.4 TLS / secure transport

Sync to a real server wants encryption. DDR-011 already framed TLS as a *library-level* wrapping `Conn` (a `Conn` that wraps another `Conn`), not a platform concern. *Options:*
- **A — `SecureClient(c: Conn, host, VAR err): Conn`** wraps a plain `Conn`; the rest of the stack is oblivious (it's still a `ReadWriteCloser`). Native backs it with the OS TLS (Secure Transport / OpenSSL / mbedTLS); wasm gets TLS *for free* because `wss://` is TLS-terminated by the browser. **Recommend A** — it composes, and it isolates the one genuinely large dependency (a TLS stack) behind a `Conn`.
- **B — defer TLS entirely**, sync over plain TCP / a trusted network / an SSH tunnel first. Legitimate for a v1 on a LAN. **Recommend as the v1 posture**, with A as the design so nothing has to change to add it.

### 3.5 Datagrams (UDP)?

The sync use case is stream-oriented (ordered, reliable). *Recommend deferring UDP* — it doesn't fit the `Conn`/stream core and wasm can't do it anyway. Add a `PacketConn` sibling only if a real datagram need appears.

## 4. Recommendation (summary)

- One `Net` module exposing `Dial` (string network), a `Listener` interface with `Accept`, and a `Serve(l, h)` helper — plus raw `Accept` for control (3.3-C).
- `Addr` opaque + printable (3.2-a); TLS as a wrapping `Conn`, designed-in but **deferred** to a plain-transport v1 (3.4-B→A).
- All values are DDR-010 `Conn`/`ReadWriteCloser` — files and sockets stay interchangeable, and client and server share the same `Handler`/`Conn` code.

## 5. Consequences

1. The **sync server is written once in Oberon** and runs on any native runtime; the same `Handler` code that serves the connection on the server also drives it on the client (DDR-017 reuses both directions).
2. Adding a transport (wasm `"ws"`, later `"webtransport"`) is a **DDR-016 backend change plus one string** — no `Net` surface change (3.1-A).
3. TLS, when wanted, slots in as a `Conn`-wrapping `Conn` with no change to any consumer (3.4).
4. The module is *thin*: it is address parsing + the DDR-011 primitives + a `Spawn`-per-connection loop. The weight is in DDR-014 (concurrency) and DDR-016 (per-runtime, especially wasm), which is the correct place for it.

## 6. Amendments this record proposes to prior records

- **DDR-010 →** promote `Addr` from named-but-abstract to the printable interface of 3.2-a; add `Listener` and `Handler` as new interfaces in the same family (non-breaking).
- **DDR-011 →** unchanged (its socket primitives are exactly what `Dial`/`Listen` lower to on native); note that wasm does **not** provide them (DDR-016).

## 7. As-built (first cut, LLVM/POSIX)

Three source files in `runtime/posix/`:

- **`Streams.Mod`** — the DDR-008/010 stream core as pure interfaces: `Reader`/`Writer`/`Closer`/`ReadWriter`/`ReadWriteCloser`. No implementation, no C sidecar, identical on every backend. This is the home DDR-010 §2 assumed but that had never been written down in code.
- **`Net.Mod`** — the portable interfaces (`Addr`, `Conn` including `Streams.ReadWriteCloser`, `Listener`, `Handler`) plus `Dial`/`Listen`/`Serve` and the private POSIX backing records (`TCPConn`/`TCPListener`/`NetAddr`). The `*Raw` procedures are weak Oberon stubs; conformance, addressing strings, and the accept loop are all in Oberon.
- **`Net_rt.c`** — the strong overrides: a thin skin over `getaddrinfo`/`socket`/`bind`/`listen`/`accept`/`connect`/`recv`/`send`/`close`, with `SIGPIPE` ignored and `SO_NOSIGPIPE`/`MSG_NOSIGNAL` where available.

Two Oberon-07 shapes worth recording for the next module in this family:

1. **Import order is significant.** A leaf module (`Errors`, `Streams`) must be listed **before** any module that transitively imports it (`Net`), or the frontend rejects it with *"invalid import order"* — the compiler assigns a module number when it first sees a dependency indirectly, and a later explicit import then collides. So `IMPORT Errors, Net, Out`, never `IMPORT Net, Out, Errors`.
2. **No method-call chaining on a call result.** `l.Addr().Str(s)` is *"not a procedure"* — a function result is not a designator you can dispatch on. Bind it first: `a := l.Addr(); a.Str(s)`.

**Open API question — `Write` has no length parameter.** Faithful to DDR-008, `Writer.Write(buf: ARRAY OF BYTE): INTEGER` writes `LEN(buf)`, and `Reader.Read(VAR buf): INTEGER` fills up to `LEN(buf)`. Because Oberon-07 has no array slices, this makes *"send the first `n` bytes of a larger buffer"* impossible without copying into an exact-sized array — a real ergonomic cost for framed protocols (DDR-017's sync verbs). Options for a follow-up: (a) keep the DDR-008 signature and let callers size buffers exactly (status quo); (b) add an explicit `n` — `Write(buf: ARRAY OF BYTE; n: INTEGER): INTEGER` / `Read(VAR buf; n)` — a small, Wirthian departure that reads the length off the call rather than the array; (c) introduce a `Buffer` type carrying `{data, len}` and write/read against it. Recommend deciding this before DDR-017, since the sync protocol is the first heavy `Write` user; **(b)** is the lightest fix and does not disturb the interface's shape.
