MODULE ConcTest;
(* Concurrency proof (DDR-014): one thread, one scheduler, a server task and
   three client tasks all in flight at once. Net.Serve accepts each connection
   and spawns an echo handler; every socket op yields cooperatively while it
   waits, so all three clients are served without threads. A serial server
   would still complete this, but the interleave (accept, dial, read, write all
   suspending into the scheduler) is what makes it concurrent. *)

  IMPORT Errors, Tasks, Net, Out;

  TYPE
    Echo = POINTER TO EchoDesc;
    EchoDesc = RECORD IMPLEMENTS Net.Handler END;

  VAR
    gL: Net.Listener;
    gAddr: ARRAY 64 OF CHAR;
    gHandler: Echo;
    gA: Net.Addr;
    gErr: Errors.Error;
    gHandled, gDone, gNextId, gClients: INTEGER;

  (* server-side: echo one message back, then stop the listener once every
     expected client has been served (unblocking the accept loop) *)
  PROCEDURE (h: Echo) Serve (c: Net.Conn);
    VAR buf: ARRAY 64 OF BYTE; n, k: INTEGER;
  BEGIN
    n := c.Read(buf, 0, LEN(buf));
    IF n > 0 THEN k := c.Write(buf, 0, n) END;
    c.Close();
    INC(gHandled);
    IF gHandled >= gClients THEN gL.Close() END
  END Serve;

  PROCEDURE Server;
  BEGIN Net.Serve(gL, gHandler, gErr)
  END Server;

  PROCEDURE Client;
    VAR id, n, k: INTEGER; c: Net.Conn; err: Errors.Error; tag: CHAR;
      msg, buf: ARRAY 1 OF BYTE;
  BEGIN
    id := gNextId; INC(gNextId);              (* self-assign an id (no closures) *)
    tag := CHR(41H + id);                      (* 'A', 'B', 'C' *)
    msg[0] := ORD(tag);
    c := Net.Dial("tcp", gAddr, err);
    Out.WriteString("client "); Out.Write(tag);
    IF (err = NIL) & (c # NIL) THEN
      k := c.Write(msg, 0, 1);
      n := c.Read(buf, 0, 1);
      IF (n = 1) & (buf[0] = msg[0]) THEN Out.WriteString(" got echo")
      ELSE Out.WriteString(" BAD echo") END;
      c.Close()
    ELSE Out.WriteString(" dial failed") END;
    Out.Ln;
    INC(gDone)
  END Client;

BEGIN
  gClients := 3; gHandled := 0; gDone := 0; gNextId := 0;
  gL := Net.Listen("tcp", "127.0.0.1:0", gErr);
  IF gL # NIL THEN
    gA := gL.Addr(); gA.Str(gAddr);
    NEW(gHandler);
    Tasks.Spawn(Server);
    Tasks.Spawn(Client); Tasks.Spawn(Client); Tasks.Spawn(Client);
    Tasks.Run;
    Out.WriteString("done: handled "); Out.WriteInt(gHandled);
    Out.WriteString(", clients "); Out.WriteInt(gDone); Out.Ln
  ELSE Out.WriteString("listen failed"); Out.Ln
  END
END ConcTest.
