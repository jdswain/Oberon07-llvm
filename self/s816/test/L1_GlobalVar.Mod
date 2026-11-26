MODULE L1_GlobalVar;
  IMPORT Out;
  VAR x, y: INTEGER;
BEGIN
  x := 42;
  y := -1;
  Out.Int(x, 1); Out.Ln();
  Out.Int(y, 1); Out.Ln();
  x := 0;
  Out.Int(x, 1); Out.Ln()
END L1_GlobalVar.
