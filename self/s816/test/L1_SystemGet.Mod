MODULE L1_SystemGet;
  IMPORT SYSTEM, Out;
  VAR x, y: INTEGER;
      addr: INTEGER;
BEGIN
  (* Write a value to memory, then read it back *)
  x := 1234;
  addr := 2000H;
  SYSTEM.PUT(0, addr, x);
  SYSTEM.GET(0, addr, y);
  Out.Int(y, 1); Out.Ln();

  (* Write and read another value *)
  x := 5678;
  addr := 2002H;
  SYSTEM.PUT(0, addr, x);
  SYSTEM.GET(0, addr, y);
  Out.Int(y, 1); Out.Ln()
END L1_SystemGet.
