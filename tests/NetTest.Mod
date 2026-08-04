MODULE NetTest;
(* Single-process TCP round-trip over Net (DDR-015). Listen on an ephemeral
   loopback port, Dial it, Accept the peer, exchange two fixed-size messages
   in both directions. connect() completes into the listen backlog, so a
   single thread can drive both ends without the DDR-014 scheduler. *)

  IMPORT Errors, Net, Out;

  PROCEDURE report (tag: ARRAY OF CHAR; err: Errors.Error): BOOLEAN;
    VAR m: ARRAY 64 OF CHAR;
  BEGIN
    IF err # NIL THEN
      err.Message(m);
      Out.WriteString(tag); Out.WriteString(": error "); Out.WriteString(m); Out.Ln
    END;
    RETURN err = NIL
  END report;

  PROCEDURE dump (tag: ARRAY OF CHAR; VAR buf: ARRAY OF BYTE; n: INTEGER);
    VAR i: INTEGER;
  BEGIN
    Out.WriteString(tag); Out.WriteString(" ("); Out.WriteInt(n); Out.WriteString("): ");
    i := 0; WHILE i < n DO Out.Write(CHR(buf[i])); INC(i) END;
    Out.Ln
  END dump;

  PROCEDURE Run;
    VAR l: Net.Listener; client, server: Net.Conn; a: Net.Addr; err: Errors.Error;
      addr, peer: ARRAY 64 OF CHAR;
      hello: ARRAY 5 OF BYTE; rep: ARRAY 4 OF BYTE; buf: ARRAY 64 OF BYTE;
      n: INTEGER; ok: BOOLEAN;
  BEGIN
    hello[0] := 68H; hello[1] := 65H; hello[2] := 6CH; hello[3] := 6CH; hello[4] := 6FH; (* "hello" *)
    rep[0] := 3FH; rep[1] := 68H; rep[2] := 69H; rep[3] := 3FH;   (* "?hi?" — reply is the [1,2) window *)

    l := Net.Listen("tcp", "127.0.0.1:0", err);
    ok := report("listen", err);
    IF ok & (l # NIL) THEN
      a := l.Addr(); a.Str(addr);
      Out.WriteString("listening on "); Out.WriteString(addr); Out.Ln;

      client := Net.Dial("tcp", addr, err); ok := report("dial", err) & ok;
      server := l.Accept(err); ok := report("accept", err) & ok;

      IF ok & (client # NIL) & (server # NIL) THEN
        a := server.RemoteAddr(); a.Str(peer);
        Out.WriteString("accepted from "); Out.WriteString(peer); Out.Ln;

        n := client.Write(hello, 0, LEN(hello));
        Out.WriteString("client wrote "); Out.WriteInt(n); Out.Ln;
        n := server.Read(buf, 0, LEN(buf)); dump("server read", buf, n);

        n := server.Write(rep, 1, 2);   (* windowed write: "hi" from offset 1 *)
        Out.WriteString("server wrote "); Out.WriteInt(n); Out.Ln;
        n := client.Read(buf, 0, LEN(buf)); dump("client read", buf, n);

        client.Close(); server.Close()
      END;
      l.Close()
    END;
    Out.WriteString("done"); Out.Ln
  END Run;

BEGIN
  Run
END NetTest.
