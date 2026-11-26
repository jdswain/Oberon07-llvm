MODULE L10_SystemAdr;
  IMPORT SYSTEM, Out;
  VAR x: INTEGER;
      addr: INTEGER;
BEGIN
  x := 42;
  addr := SYSTEM.ADR(x);
  (* Verify ADR returns a non-zero address *)
  IF addr # 0 THEN
    Out.Int(1, 1); Out.Ln()
  ELSE
    Out.Int(0, 1); Out.Ln()
  END;

  (* Write through address using GET/PUT: in the variable's bank (a
     module's variables are in whatever bank the loader put them, .816 v4) *)
  SYSTEM.PUT(SYSTEM.BANK(x), addr, 99);
  Out.Int(x, 1); Out.Ln()
END L10_SystemAdr.
