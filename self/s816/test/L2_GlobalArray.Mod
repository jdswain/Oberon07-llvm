MODULE L2_GlobalArray;
  IMPORT Out;
  VAR a: ARRAY 3 OF INTEGER;
      i, sum: INTEGER;
BEGIN
  a[0] := 100; a[1] := 200; a[2] := 300;
  sum := 0;
  i := 0;
  WHILE i < 3 DO
    Out.Int(a[i], 1); Out.Ln();
    sum := sum + a[i];
    i := i + 1
  END;
  Out.Int(sum, 1); Out.Ln()
END L2_GlobalArray.
