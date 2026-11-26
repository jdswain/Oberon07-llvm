MODULE L10_SystemTrbTsb;
  IMPORT SYSTEM, Out;
  VAR val: INTEGER;
      addr: INTEGER;
BEGIN
  addr := 2000H;

  (* Start with 0 *)
  SYSTEM.PUT(0, addr, 0);

  (* TSB: set bits 0 and 2 (mask = 5) *)
  SYSTEM.TSB(addr, 5);
  SYSTEM.GET(0, addr, val);
  Out.Int(val, 1); Out.Ln();  (* expect 5 *)

  (* TSB: set bit 1 (mask = 2) *)
  SYSTEM.TSB(addr, 2);
  SYSTEM.GET(0, addr, val);
  Out.Int(val, 1); Out.Ln();  (* expect 7 *)

  (* TRB: clear bit 0 (mask = 1) *)
  SYSTEM.TRB(addr, 1);
  SYSTEM.GET(0, addr, val);
  Out.Int(val, 1); Out.Ln();  (* expect 6 *)

  (* TRB: clear bits 1 and 2 (mask = 6) *)
  SYSTEM.TRB(addr, 6);
  SYSTEM.GET(0, addr, val);
  Out.Int(val, 1); Out.Ln()   (* expect 0 *)
END L10_SystemTrbTsb.
