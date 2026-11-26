MODULE L8_RealConvert;
  IMPORT Out;
  VAR x: REAL; i: INTEGER;
BEGIN
  i := 42;
  x := FLT(i);
  Out.Int(FLOOR(x), 1); Out.Ln();
  x := 3.7;
  i := FLOOR(x);
  Out.Int(i, 1); Out.Ln()
END L8_RealConvert.
