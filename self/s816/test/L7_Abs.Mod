MODULE L7_Abs;
  IMPORT Out;
  VAR x: INTEGER;
BEGIN
  (* Const ABS - compile time *)
  Out.Int(ABS(10), 1); Out.Ln();
  Out.Int(ABS(-10), 1); Out.Ln();
  Out.Int(ABS(0), 1); Out.Ln();
  (* Variable ABS - runtime *)
  x := 10;
  Out.Int(ABS(x), 1); Out.Ln();
  x := -10;
  Out.Int(ABS(x), 1); Out.Ln();
  x := 0;
  Out.Int(ABS(x), 1); Out.Ln()
END L7_Abs.
