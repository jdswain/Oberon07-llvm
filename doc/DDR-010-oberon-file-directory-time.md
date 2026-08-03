# Design Decision Record 010: File, Directory, and Time Modules

**Author:** Jason Swain
**Date:** 2026-07-14
**Status:** Accepted (semantic design). Depends on the now-ratified error convention (§2.1) and defines the Time types that the networking module (DDR-009) requires.
**Relationship to prior records:** Standalone sibling to DDRs 001–009. It builds on DDR-008 (nominal interfaces), consumes DDR-009 (the `Reader`/`Writer`/`Closer` stream core), and defines the `Time` types DDR-009 left as a dependency. The low-level syscall/platform layer that the *implementations* bottom out into is specified separately in **DDR-011**. Prior documents are not modified; §7 lists the amendments they would receive.

---

## 1. Context

DDR-009 defined a networking library over a small stream core (`Reader`, `Writer`, `Closer` and their inclusions). Two gaps remained: files/directories were undefined, and `Time` was named as a dependency (file timestamps and socket timeouts) but not specified. A design requirement was added: a socket and a file should share the same stream interface rather than each defining its own.

This record specifies `File`, `FileSystem`, `Directory`, and `Time`, and fixes how files and sockets share the stream core. It also records the ratification of the error convention, which was the last blocking item for building any of this.

---

## 2. Decisions

### 2.1 Error convention — ratified
**Status:** Accepted (resolves the parent DDR's §3 "Error model" open item; promotes DDR-009's provisional `Error` interface to Accepted).

Errors are signalled by a trailing **`VAR err: Error`** out-parameter, with `NIL` meaning success. `Error` is the DDR-009 interface (anything that can describe itself):

```
TYPE Error = INTERFACE PROCEDURE Msg(): String END;
```

**Rationale.** It carries Go's best error idea — error-as-interface, so failures are values that describe themselves and compose — but delivers the value through Oberon's existing out-parameter convention, adding nothing to the language (no tuples, no exceptions). It is idiomatic Oberon and close in spirit to Go's `(value, error)` return without the tuple machinery.

### 2.2 Files and sockets share the stream core by *inclusion*, not extension
**Status:** Accepted

Neither `File` nor `Conn` extends the other, and neither extends a shared stream type by inheritance. Both **include** the same named stream interface, `ReadWriteCloser` (DDR-009).

**Rationale.** Seekability and peer-addressing do not cross over: a file has a position but no peer address; a socket has a peer address but no meaningful seek. If either extended the other, one would inherit a method it cannot honour. The only thing genuinely shared is the read/write/close triple, which is exactly what shared inclusion expresses.

**Nominal subtlety (DDR-008).** "Same interface" must be achieved by *both including one named interface*, not by aliasing. `Stream = INTERFACE ReadWriteCloser END` would be a **distinct** interface with the same method set, and under nominal conformance a record implementing `ReadWriteCloser` would **not** implement `Stream` unless it declared so. Oberon-07 has no type aliases to sidestep this, so the stream interface simply *is* `ReadWriteCloser` by that name, and both `File` and `Conn` include it.

### 2.3 File, FileInfo, Seeker
**Status:** Accepted

```
TYPE
  Seeker = INTERFACE
    PROCEDURE Seek(offset: LONGINT; whence: INTEGER; VAR err: Error): LONGINT
    (* whence: SeekStart, SeekCurrent, SeekEnd; returns new absolute position *)
  END;

  File = INTERFACE
    ReadWriteCloser;           (* the shared stream core — identical to a socket's *)
    Seeker;                    (* file-only; sockets do not include this *)
    PROCEDURE Stat(VAR err: Error): FileInfo;
    PROCEDURE Sync(VAR err: Error)      (* flush to storage *)
  END;

  FileInfo = INTERFACE
    PROCEDURE Name(): String;
    PROCEDURE Size(): LONGINT;
    PROCEDURE Mode(): INTEGER;          (* permission/type bits *)
    PROCEDURE ModTime(): DateTime;      (* ← Time dependency, wall-clock; see §2.6 *)
    PROCEDURE IsDir(): BOOLEAN
  END;
```

`FileInfo.ModTime` is the exact point at which file timestamps require `DateTime`, so §2.6 must compile before `File`.

**Rider (optional, deferred — nice to have, not essential).** Oberon's native `Files` module keeps position *off* the file, in separate `Rider` cursor objects, allowing several independent heads on one positionless file — arguably cleaner than POSIX's single shared position. It does not unify with sockets, so the shared stream layer stays Go-flavoured (`Reader`/`Writer` with implicit position). A Rider-style random-access API may be offered later as a **file-only** addition layered on `Seeker`; it is explicitly non-essential and costs the shared layer nothing.

### 2.4 FileSystem — the portability seam
**Status:** Accepted

```
TYPE
  FileSystem = INTERFACE
    PROCEDURE Open(name: String; flags: SET; VAR err: Error): File;
    PROCEDURE Stat(name: String; VAR err: Error): FileInfo;
    PROCEDURE Remove(name: String; VAR err: Error);
    PROCEDURE Rename(old, new: String; VAR err: Error);
    PROCEDURE MkDir(name: String; mode: INTEGER; VAR err: Error);
    PROCEDURE OpenDir(name: String; VAR err: Error): Directory
  END;
```

Modelled on Go's `io/fs.FS`. The library written above `FileSystem` is written once; the hosted/C backend and the OS16 backend are two *implementations* of this one interface (real disk, and later a zip or in-memory tree, may also coexist at runtime). No signature here changes between platforms.

### 2.5 Directory — an iterator, not a bulk array
**Status:** Accepted

```
TYPE
  DirEntry = INTERFACE
    PROCEDURE Name(): String;
    PROCEDURE IsDir(): BOOLEAN;
    PROCEDURE Info(VAR err: Error): FileInfo   (* lazy: may stat on demand *)
  END;

  Directory = INTERFACE
    Closer;
    PROCEDURE Next(VAR entry: DirEntry; VAR err: Error): BOOLEAN
    (* FALSE at end; err distinguishes clean end from failure *)
  END;
```

`Next`-style iteration keeps memory bounded on OS16 (no whole-listing allocation) and is the shape a closure-based `each` would later wrap if the iteration protocol from the parent DDR's §3 is adopted.

### 2.6 Time — monotonic and wall-clock are *different types*
**Status:** Accepted

The two stated uses want two different clocks. File timestamps want wall-clock time, which can jump (NTP, manual set); timeouts want a monotonic clock that only moves forward, because a wall-clock adjustment mid-wait silently breaks a timeout. The types are kept distinct so the type system prevents the misuse rather than documenting against it.

```
TYPE
  Duration = LONGINT;    (* nanoseconds; distinct-type if the compiler allows,
                            else a named record. 64-bit ns spans ~292 years *)

  Instant = INTERFACE     (* MONOTONIC — timeouts/measuring; no wall meaning *)
    PROCEDURE Since(earlier: Instant): Duration;
    PROCEDURE Add(d: Duration): Instant
  END;

  DateTime = INTERFACE    (* WALL-CLOCK, stored as UTC — file timestamps *)
    PROCEDURE UnixNanos(): LONGINT;
    PROCEDURE Add(d: Duration): DateTime;
    PROCEDURE Sub(other: DateTime): Duration
  END;

  Clock = INTERFACE       (* the source; two readings, deliberately separate *)
    PROCEDURE Now(): DateTime;      (* wall *)
    PROCEDURE Monotonic(): Instant  (* monotonic *)
  END;
```

**Rationale.** Go conflates both into `time.Time` (which secretly carries a monotonic reading) — a known footgun. Rust splits `Instant` (monotonic) from `SystemTime` (wall-clock); for a minimal language the split is worth adopting explicitly. Making `Clock` an interface also yields a fake clock for tests and is the seam where OS16's timer and the hosted backend's `clock_gettime` plug in differently.

### 2.7 Timezone — deferred, and safe to defer
**Status:** Deferred (non-breaking)

`DateTime` is stored as **UTC** (`UnixNanos` is unambiguous). Timezone becomes a later *interpretation* layer mapping a UTC instant plus a zone to a local rendering for display. Because the stored representation is already unambiguous, adding zones later changes no stored value and no existing signature — purely additive formatting. The prohibition is on storing *local* time now, which is the version that is painful to fix later. Deferral is safe precisely because the base type is UTC.

---

## 3. Correction to DDR-009 — socket deadlines use `Instant`

DDR-009's placeholder `SetTimeout(ms: INTEGER)` is replaced by deadline methods taking `Instant` (monotonic — because they are timeouts, not timestamps):

```
  Conn = INTERFACE
    ReadWriteCloser;
    PROCEDURE LocalAddr(): Addr;
    PROCEDURE RemoteAddr(): Addr;
    PROCEDURE SetReadDeadline(t: Instant; VAR err: Error);
    PROCEDURE SetWriteDeadline(t: Instant; VAR err: Error)
  END;
```

---

## 4. Implementation architecture (summary; detail in DDR-011)

- Every interface above is the single **portable** surface, defined once.
- The **hosted/LLVM backend** implements each via libc/POSIX (`File.Read`→`read`, `Seek`→`lseek`, `FileSystem.Open`→`open`, `Clock.Now`→`clock_gettime(CLOCK_REALTIME)`, `Monotonic`→`CLOCK_MONOTONIC`).
- The **OS16 backend** implements each via kernel syscalls plus the kernel code behind them.
- The set of primitives these implementations require, and whether that same primitive layer can serve as the compilers' runtime interface, is specified in **DDR-011**.

---

## 5. Consequences

1. A socket and a file are interchangeable wherever only the stream core is needed, because both include `ReadWriteCloser` — the stated goal, achieved by inclusion.
2. `Seeker` cleanly separates the file-only capability, so nothing forces a socket to pretend to seek.
3. The monotonic/wall split means a clock adjustment cannot corrupt an in-flight timeout — a class of bug removed by construction.
4. UTC storage makes timezone a safe deferral rather than a latent migration.
5. `FileSystem`, `Clock`, and the stream interfaces are the per-backend implementation seams; no library signature changes between the hosted and OS16 targets.

---

## 6. Blocking dependencies

- **Error convention:** ratified here (§2.1); no longer blocking.
- **Time:** defined here (§2.6); the file, directory, and socket modules all import it, so it is settled in the same pass rather than after.
- **Built-in maps** (parent §3): still open, still hidden behind interfaces (DDR-009's `Header`); does not block this record.

---

## 7. Amendments this record makes to prior DDRs

- **Parent §3 "Error model" →** resolved: `VAR err: Error` convention (§2.1), Accepted.
- **DDR-009 `Error` interface →** promoted from provisional to Accepted.
- **DDR-009 `Conn.SetTimeout` →** replaced by `SetReadDeadline`/`SetWriteDeadline` on `Instant` (§3).
- **DDR-009 Time dependency →** discharged by §2.6.
- **No change** to DDRs 001–008.
