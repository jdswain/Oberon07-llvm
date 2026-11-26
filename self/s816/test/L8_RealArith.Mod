MODULE L8_RealArith;
  IMPORT Out;
  VAR a, b, c: REAL;
BEGIN
  a := 3.0; b := 2.0;
  c := a + b;
  Out.Int(FLOOR(c), 1); Out.Ln();
  c := a - b;
  Out.Int(FLOOR(c), 1); Out.Ln();
  c := a * b;
  Out.Int(FLOOR(c), 1); Out.Ln();
  c := a / b;
  Out.Int(FLOOR(c), 1); Out.Ln()
END L8_RealArith.
