MODULE L10_SystemBit;
  IMPORT SYSTEM, Out;
  VAR addr, val: INTEGER;
      b: BOOLEAN;
BEGIN
  addr := 2000H;
  SYSTEM.PUT(0, addr, 5);  (* binary 0101 *)

  (* Test bit 0 - should be TRUE *)
  b := SYSTEM.BIT(addr, 0);
  Out.Bool(b); Out.Ln();

  (* Test bit 1 - should be FALSE *)
  b := SYSTEM.BIT(addr, 1);
  Out.Bool(b); Out.Ln();

  (* Test bit 2 - should be TRUE *)
  b := SYSTEM.BIT(addr, 2);
  Out.Bool(b); Out.Ln();

  (* Test bit 3 - should be FALSE *)
  b := SYSTEM.BIT(addr, 3);
  Out.Bool(b); Out.Ln();

  (* Test with variable bit number *)
  val := 2;
  b := SYSTEM.BIT(addr, val);
  Out.Bool(b); Out.Ln();

  val := 1;
  b := SYSTEM.BIT(addr, val);
  Out.Bool(b); Out.Ln()
END L10_SystemBit.
