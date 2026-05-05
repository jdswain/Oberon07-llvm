MODULE SysClient;
  IMPORT SysProvider;

  (* Round-trips: get a 64-bit address from another module, write
     through it, read it back. If the symbol-file unification dropped
     the LONGINT down to INTEGER, the i64 would silently truncate. *)
  PROCEDURE RoundTrip*(): INTEGER;
    VAR cell: INTEGER;
        a: LONGINT;
  BEGIN
    cell := 0;
    a := SysProvider.GetAdr(cell);
    SysProvider.Write(a, 42424242);
    RETURN SysProvider.Read(a)
  END RoundTrip;

END SysClient.
