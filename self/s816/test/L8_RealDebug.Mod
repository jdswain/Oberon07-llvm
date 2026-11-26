MODULE L8_RealDebug;
  IMPORT Out;

  VAR x, y: REAL;

BEGIN
  x := 0.5;
  y := 10.0;
  x := x * y;
  Out.Int(FLOOR(x), 1); Out.Ln;

  x := 0.4;
  y := 10.0;
  x := x * y;
  Out.Int(FLOOR(x), 1); Out.Ln
END L8_RealDebug.
