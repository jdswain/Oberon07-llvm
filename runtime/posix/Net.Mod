MODULE Net;
(* Dial / Listen / Serve over the DDR-010 stream core (DDR-015).

   The portable surface: `Dial` gives a client a `Conn`; `Listen` gives a
   server a `Listener` whose `Accept` yields `Conn`s; `Serve` is the
   ten-line accept loop on top. A `Conn` INCLUDES Streams.ReadWriteCloser
   (DDR-010 §2), so a socket and a file are the same value to any consumer.

   This is the hosted/POSIX backing (DDR-016): the raw *Raw procedures are
   weak Oberon stubs overridden by the strong C definitions in Net_rt.c,
   which are a thin skin over getaddrinfo/socket/bind/listen/accept/connect/
   send/recv/close. `network` is a string ("tcp"/"tcp4") so DDR-016 can add
   "ws" for wasm with no surface change (DDR-015 §3.1-A). TLS, datagrams,
   and deadlines are designed-in elsewhere but not in this first cut. *)

  IMPORT Streams, Errors, Tasks;

  TYPE
    (* --- portable interfaces (DDR-010 / DDR-015) --- *)
    Addr* = INTERFACE
      PROCEDURE Network (VAR s: ARRAY OF CHAR);   (* "tcp" *)
      PROCEDURE Str (VAR s: ARRAY OF CHAR)         (* "host:port" *)
    END;

    Conn* = INTERFACE
      Streams.ReadWriteCloser;
      PROCEDURE LocalAddr (): Addr;
      PROCEDURE RemoteAddr (): Addr
    END;

    Listener* = INTERFACE
      Streams.Closer;
      PROCEDURE Accept (VAR err: Errors.Error): Conn;
      PROCEDURE Addr (): Addr
    END;

    Handler* = INTERFACE
      PROCEDURE Serve (c: Conn)
    END;

    (* --- POSIX backing (private) --- *)
    NetAddr = POINTER TO NetAddrDesc;
    NetAddrDesc = RECORD IMPLEMENTS Addr
      net: ARRAY 8 OF CHAR;
      str: ARRAY 64 OF CHAR
    END;

    TCPConn = POINTER TO TCPConnDesc;
    TCPConnDesc = RECORD IMPLEMENTS Conn
      fd: INTEGER;
      local, remote: NetAddr
    END;

    TCPListener = POINTER TO TCPListenerDesc;
    TCPListenerDesc = RECORD IMPLEMENTS Listener
      fd: INTEGER;
      addr: NetAddr
    END;

    (* a spawned per-connection handler: the object carries the (h, c) state a
       bare Tasks.Body procedure could not (no closures) *)
    connJob = POINTER TO connJobDesc;
    connJobDesc = RECORD IMPLEMENTS Tasks.Task
      h: Handler;
      c: Conn
    END;

  (* ----- raw C bridges (Net_rt.c). Exported so the empty bodies get weak
     linkage and the C definitions override them; not for user code.
     res: 0 = ok, otherwise a host errno. fd: a socket descriptor, -1 on
     failure. ----- *)

  PROCEDURE DialRaw* (host, port: ARRAY OF CHAR; VAR fd: INTEGER; VAR res: INTEGER);
  BEGIN
  END DialRaw;

  PROCEDURE ListenRaw* (host, port: ARRAY OF CHAR; VAR fd: INTEGER; VAR res: INTEGER);
  BEGIN
  END ListenRaw;

  PROCEDURE AcceptRaw* (lfd: INTEGER; VAR fd: INTEGER; VAR res: INTEGER;
                        VAR peer: ARRAY OF CHAR);
  BEGIN
  END AcceptRaw;

  PROCEDURE ReadRaw* (fd: INTEGER; VAR buf: ARRAY OF BYTE; start, len: INTEGER): INTEGER;
  BEGIN RETURN -1
  END ReadRaw;

  PROCEDURE WriteRaw* (fd: INTEGER; buf: ARRAY OF BYTE; start, len: INTEGER): INTEGER;
  BEGIN RETURN -1
  END WriteRaw;

  PROCEDURE CloseRaw* (fd: INTEGER);
  BEGIN
  END CloseRaw;

  PROCEDURE LocalAddrRaw* (fd: INTEGER; VAR a: ARRAY OF CHAR);
  BEGIN
  END LocalAddrRaw;

  (* ----- small helpers ----- *)

  PROCEDURE copy (src: ARRAY OF CHAR; VAR dst: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE (i < LEN(src)) & (i < LEN(dst) - 1) & (src[i] # 0X) DO
      dst[i] := src[i]; INC(i)
    END;
    dst[i] := 0X
  END copy;

  PROCEDURE isTCP (network: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    RETURN (network = "tcp") OR (network = "tcp4")
  END isTCP;

  (* Split "host:port" at the (last) colon. Empty host = wildcard bind. *)
  PROCEDURE splitHostPort (addr: ARRAY OF CHAR; VAR host, port: ARRAY OF CHAR);
    VAR i, k, colon: INTEGER;
  BEGIN
    colon := -1; i := 0;
    WHILE (i < LEN(addr)) & (addr[i] # 0X) DO
      IF addr[i] = ":" THEN colon := i END;
      INC(i)
    END;
    i := 0;
    IF colon >= 0 THEN
      WHILE (i < colon) & (i < LEN(host) - 1) DO host[i] := addr[i]; INC(i) END
    END;
    host[i] := 0X;
    IF colon >= 0 THEN i := colon + 1 ELSE i := 0 END;
    k := 0;
    WHILE (i < LEN(addr)) & (addr[i] # 0X) & (k < LEN(port) - 1) DO
      port[k] := addr[i]; INC(k); INC(i)
    END;
    port[k] := 0X
  END splitHostPort;

  PROCEDURE mkErr (res: INTEGER; msg: ARRAY OF CHAR; VAR err: Errors.Error);
  BEGIN
    err := Errors.Error.Create(res, msg)
  END mkErr;

  PROCEDURE newConn (fd: INTEGER; remote: ARRAY OF CHAR): TCPConn;
    VAR c: TCPConn;
  BEGIN
    NEW(c); c.fd := fd;
    NEW(c.local); copy("tcp", c.local.net); LocalAddrRaw(fd, c.local.str);
    NEW(c.remote); copy("tcp", c.remote.net); copy(remote, c.remote.str);
    RETURN c
  END newConn;

  (* ----- Addr methods ----- *)

  PROCEDURE (a: NetAddr) Network (VAR s: ARRAY OF CHAR);
  BEGIN copy(a.net, s)
  END Network;

  PROCEDURE (a: NetAddr) Str (VAR s: ARRAY OF CHAR);
  BEGIN copy(a.str, s)
  END Str;

  (* ----- Conn methods ----- *)

  PROCEDURE (c: TCPConn) Read (VAR buf: ARRAY OF BYTE; start, len: INTEGER): INTEGER;
  BEGIN RETURN ReadRaw(c.fd, buf, start, len)
  END Read;

  PROCEDURE (c: TCPConn) Write (buf: ARRAY OF BYTE; start, len: INTEGER): INTEGER;
  BEGIN RETURN WriteRaw(c.fd, buf, start, len)
  END Write;

  PROCEDURE (c: TCPConn) Close ();
  BEGIN CloseRaw(c.fd); c.fd := -1
  END Close;

  PROCEDURE (c: TCPConn) LocalAddr (): Addr;
  BEGIN RETURN c.local
  END LocalAddr;

  PROCEDURE (c: TCPConn) RemoteAddr (): Addr;
  BEGIN RETURN c.remote
  END RemoteAddr;

  (* ----- Listener methods ----- *)

  PROCEDURE (l: TCPListener) Accept (VAR err: Errors.Error): Conn;
    VAR fd, res: INTEGER; peer: ARRAY 64 OF CHAR; c: TCPConn;
  BEGIN
    c := NIL; fd := -1; res := 0;
    AcceptRaw(l.fd, fd, res, peer);
    IF res # 0 THEN mkErr(res, "accept failed", err)
    ELSE err := NIL; c := newConn(fd, peer)
    END;
    RETURN c
  END Accept;

  PROCEDURE (l: TCPListener) Addr (): Addr;
  BEGIN RETURN l.addr
  END Addr;

  PROCEDURE (l: TCPListener) Close ();
  BEGIN CloseRaw(l.fd); l.fd := -1
  END Close;

  (* ----- module surface ----- *)

  PROCEDURE Dial* (network, address: ARRAY OF CHAR; VAR err: Errors.Error): Conn;
    VAR host, port: ARRAY 64 OF CHAR; fd, res: INTEGER; c: TCPConn;
  BEGIN
    c := NIL;
    IF ~isTCP(network) THEN mkErr(1, "unsupported network", err)
    ELSE
      splitHostPort(address, host, port);
      fd := -1; res := 0;
      DialRaw(host, port, fd, res);
      IF res # 0 THEN mkErr(res, "dial failed", err)
      ELSE err := NIL; c := newConn(fd, address)
      END
    END;
    RETURN c
  END Dial;

  PROCEDURE Listen* (network, address: ARRAY OF CHAR; VAR err: Errors.Error): Listener;
    VAR host, port: ARRAY 64 OF CHAR; fd, res: INTEGER; l: TCPListener;
  BEGIN
    l := NIL;
    IF ~isTCP(network) THEN mkErr(1, "unsupported network", err)
    ELSE
      splitHostPort(address, host, port);
      fd := -1; res := 0;
      ListenRaw(host, port, fd, res);
      IF res # 0 THEN mkErr(res, "listen failed", err)
      ELSE
        err := NIL;
        NEW(l); l.fd := fd;
        NEW(l.addr); copy("tcp", l.addr.net); LocalAddrRaw(fd, l.addr.str)
      END
    END;
    RETURN l
  END Listen;

  PROCEDURE (j: connJob) Run ();
  BEGIN j.h.Serve(j.c)
  END Run;

  (* Concurrent accept loop (DDR-014 / DDR-015 §3.3): each accepted connection
     is handed to a fresh task, so the handler runs while the loop goes back to
     accepting. Accept itself yields cooperatively while it waits, so a single
     thread serves many connections at once. Runs inside Tasks.Run; returns
     when Accept fails, e.g. after the listener is closed. *)
  PROCEDURE Serve* (l: Listener; h: Handler; VAR err: Errors.Error);
    VAR c: Conn; j: connJob;
  BEGIN
    c := l.Accept(err);
    WHILE err = NIL DO
      NEW(j); j.h := h; j.c := c;
      Tasks.SpawnTask(j);
      c := l.Accept(err)
    END
  END Serve;

END Net.
