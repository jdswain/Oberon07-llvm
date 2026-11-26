MODULE L3_ArrayCopy;
  IMPORT Out;
  VAR a, b: ARRAY 4 OF INTEGER;
BEGIN
  a[0] := 10; a[1] := 20; a[2] := 30; a[3] := 40;
  b := a;
  Out.Int(b[0], 1); Out.Ln();
  Out.Int(b[1], 1); Out.Ln();
  Out.Int(b[2], 1); Out.Ln();
  Out.Int(b[3], 1); Out.Ln()
END L3_ArrayCopy.
