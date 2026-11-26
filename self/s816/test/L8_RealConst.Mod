MODULE L8_RealConst;
  IMPORT Out;
  CONST pi = 3.14159;
  VAR x, y: REAL;
BEGIN
  x := 3.0;
  y := pi;
  Out.Int(FLOOR(x), 1); Out.Ln();
  Out.Int(FLOOR(y), 1); Out.Ln();
  x := -1.5;
  Out.Int(FLOOR(x), 1); Out.Ln();
  x := 0.0;
  Out.Int(FLOOR(x), 1); Out.Ln()
END L8_RealConst.
