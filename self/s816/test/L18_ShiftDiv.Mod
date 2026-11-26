MODULE L18_ShiftDiv; (* a runtime shift count from a record field, whose
   pointer takes registers before the value is loaded; power-of-two DIV
   of a procedure's result *)
  IMPORT Out, HeapManager;
  TYPE R = POINTER TO RD; RD = RECORD a, drive: INTEGER END;
  VAR r: R; n, x: INTEGER;

  PROCEDURE G(x: INTEGER): INTEGER;
  BEGIN RETURN x
  END G;

  PROCEDURE P(a, b: INTEGER);
  BEGIN Out.Int(a, 5); Out.Int(b, 5)
  END P;

  PROCEDURE Q(d: R);
  BEGIN P(1, ASL(10H, d.drive) + 0CH + d.drive)
  END Q;

BEGIN
  NEW(r); r.drive := 1; n := 1;
  P(1, ASL(10H, r.drive) + 0CH); P(1, ASL(10H, n) + 0CH); Q(r); Out.Ln;
  x := ASL(10H, r.drive) + 0CH + r.drive; Out.Int(x, 5);
  x := LSR(100H, r.drive) + r.drive; Out.Int(x, 5);
  x := ROL(100H, r.drive) + r.drive; Out.Int(x, 5);
  x := AND(0FFH, r.drive) + r.drive; Out.Int(x, 5); Out.Ln;
  Out.Int(G(208) DIV 64, 5); Out.Int(G(208) DIV 2, 5); Out.Int(G(-208) DIV 64, 5);
  Out.Int(G(208) MOD 64, 5); Out.Int(1 + G(208) DIV 16, 5); Out.Ln
END L18_ShiftDiv.
