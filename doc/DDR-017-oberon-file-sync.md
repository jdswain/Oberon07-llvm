# Design Decision Record 017: File-Sync Protocol (`oed` ↔ Server)

**Author:** Jason Swain
**Date:** 2026-07-28
**Status:** **Draft — options open.** This is the *application* the networking stack exists to serve; it is also where the product decisions live (what "sync" means). §3 is the main fork; author decides §3/§4/§5.
**Relationship to prior records:** Consumes **DDR-015** (`Net`: the client `Dial`s, the server `Serve`s), **DDR-010** (`Files`/`FileInfo`/`Time` on both ends), **DDR-014** (a task per connection; background sync without freezing the editor), and **DDR-013** (the `Handler`/`Conn` interfaces). Reuses one Oberon codebase on both ends — the stated goal of writing the server in Oberon.

---

## 1. Context

The concrete target: `oed` (the editor) reads files from, and syncs edits to, a server; the server is written in Oberon and reuses the same modules. Everything above (DDRs 013–016) is scaffolding for this. This record specifies the *protocol and semantics* — what messages cross the `Conn`, and what "sync" is allowed to mean — because those are the decisions that determine whether the whole stack is simple or a distributed-systems project.

The governing instinct should be **minimal**: the first useful version is "open a file that lives on the server, edit it, save it back," which is barely more than remote file I/O. Everything past that (bidirectional, offline, merge) is a step-change in difficulty and should be an explicit, separately-decided increment.

## 2. Reuse — the same `File` surface on both ends

The key economy: the server's request handler operates on its **local `Files`** (DDR-010) to answer the client, and the client presents the *remote* files to `oed` through the *same* `File`/`ReadWriteCloser` interface. So `oed` opens a `File` whether it is local or remote; a `RemoteFile` is a `File` implementation whose `Read`/`Write` marshal to the server over a `Conn`. This is exactly the DDR-010 promise (a socket and a file are the same stream) turned into an application: **`oed` never learns whether a file is local or remote.** That single decision — model remote files as a `FileSystem`/`File` implementation, not a bespoke API — is the backbone of this record.

```
  (* client side: a remote FileSystem backed by a Conn *)
  fs := Sync.Mount(conn);          (* a DDR-010 FileSystem *)
  f  := fs.Open("Kernel.Mod", err);(* a DDR-010 File; Read/Write marshal over conn *)
```

## 3. What "sync" means — the main decision

Ordered by difficulty; each is a superset of the one above.

- **Level 0 — Remote file access (no "sync").** `Open`/`Read`/`Write`/`Close`/`List`/`Stat`/`Delete` marshalled to the server, which acts on its filesystem. `oed` edits files that *live* on the server; "saving" is a remote write. No local copy, no offline, no conflicts. **Recommended first target** — it is remote `Files` and nothing more, and it already delivers "read a file from the server."
- **Level 1 — One-way pull with local cache.** Client keeps a local copy; `Pull` refreshes changed files (server → client). Adds change detection (§4) but no write-back conflicts. Good for "distribute the library to a device."
- **Level 2 — Two-way, last-writer-wins.** Client also pushes; on collision the newer timestamp wins, the loser is kept as a `.conflict` copy. Adds conflict *detection* and a dumb but safe resolution. **Recommended second target** — this is real sync for a single user across a couple of machines, without a merge engine.
- **Level 3 — Two-way with content merge / offline queue.** Three-way merge, offline edit queues, vector clocks. This is a distributed-systems undertaking. **Defer**; record it so Levels 0–2 don't foreclose it, but do not build it speculatively.

**Recommendation:** ship **Level 0** first (it is remote `Files`), design the protocol so **Level 2** drops in (carry version metadata from the start, §4), and explicitly defer Level 3.

## 4. Change detection & conflict metadata

Even Level 0 benefits from carrying a **version token** per file so Levels 1–2 need no protocol change. *Options:*
- **(a) mtime + size** (DDR-010 `FileInfo`) — cheap, no read; good enough to *detect* change, weak against clock skew and same-size edits.
- **(b) content hash** (e.g. a 64/128-bit digest) — reliable change detection and dedup, costs a read to compute.
- **(c) monotonic server revision** — the server assigns an increasing revision per file/commit; unambiguous and skew-free, but only the server can mint it (fine — the server is authoritative).
- **Recommendation:** **(c) server revision as the source of truth**, with **(a) mtime** as a cheap client-side "might have changed" pre-filter and **(b) hash** only when disambiguation is needed. Carry the revision token in every `Stat`/`Read`/`Write` from Level 0 on.

Conflict rule (Level 2): compare the client's base revision to the server's current; if the server moved, it's a conflict → last-writer-wins by revision, loser saved as `name.conflict-<rev>`. Simple, safe, no data loss.

## 5. Wire protocol shape

A small request/response protocol over the DDR-015 `Conn` (which is WebSocket-framed on wasm, raw or WS-framed on native — DDR-016). *Options:*
- **(a) Verb + length-prefixed payload, binary.** `OPEN path`, `READ handle off len`, `WRITE handle off data`, `STAT path`, `LIST path`, `DELETE path`, each reply carrying `err` (DDR-009) + revision. Compact, streams well, maps directly onto `Files`/`FileInfo`. **Recommended.**
- **(b) Text/line protocol** (like SMTP/Gopher). Debuggable by hand, but awkward for binary file bodies and slower. Reasonable for a bring-up spike, not the final wire.
- **(c) Piggyback on an existing protocol (HTTP verbs, WebDAV).** Interops with generic tools, but drags in HTTP semantics and doesn't reuse the Oberon `Files` shape cleanly. **Not recommended** — we control both ends; a bespoke minimal verb set is simpler and reuses `Files` 1:1.

**Framing** is length-prefixed messages (a 4-byte length + body) over the byte stream; on wasm each maps to a WebSocket message. **Errors** ride the DDR-009 `VAR err: Error` convention, serialised as a code + message per reply. **Concurrency:** one request in flight per `Conn` to start (simple); add request IDs for pipelining only if latency demands (Level 1+).

**Transfer granularity:** whole-file `Read`/`Write` first (matches editor save/load and `Files`). Add **rsync-style block deltas** only if large files over slow links prove it necessary — record as a deferred optimisation, not a v1 feature.

## 6. Recommendation (summary)

1. Model remote files as a **DDR-010 `FileSystem`/`File`** so `oed` is oblivious to location (§2).
2. Ship **Level 0** (remote file access) first; design for **Level 2** (two-way, last-writer-wins, `.conflict` copies) and **defer Level 3** (merge/offline) (§3).
3. Make the **server authoritative with a monotonic revision** per file; carry it from Level 0 (§4).
4. **Binary verb protocol**, length-prefixed, `err`+revision on every reply, whole-file transfer, one request per connection to start (§5).
5. The server is a DDR-015 `Serve(l, h)` whose `Handler` answers requests against its local `Files`; the client's `RemoteFile` marshals `Files` calls over the `Conn`. **One protocol module, used by both.**

## 7. Consequences

1. `oed` gains "open/save a server file" with **no editor changes** beyond opening a `File` from a mounted remote `FileSystem` — the whole stack pays off as a one-line `Mount`.
2. The **server is small**: an accept loop + a handler that maps verbs to `Files` calls; it is the mirror image of the client's `RemoteFile`, so the two are written and tested together.
3. Choosing **server-authoritative revisions** now is what lets Level 2 arrive later without a wire change — the one piece of forward-design worth doing before Level 0 ships.
4. wasm gets remote files identically to native (the `Conn` is a WebSocket underneath — DDR-016), so `oed`-in-the-browser syncs to the same server as `oed`-native with the same code.

## 8. Amendments this record proposes to prior records

- **DDR-010 →** none required; this record is a *consumer* of `FileSystem`/`File`/`FileInfo`. If a `revision` field is wanted on `FileInfo`, add it there (non-breaking).
- **DDR-015 →** none; `Serve` + `Handler` + `Dial` are exactly the surface used.
- **No change** to DDRs 011–014, 016 beyond the cross-references above.
