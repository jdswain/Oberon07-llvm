MODULE L2_Array;
  IMPORT Out;
  VAR i, sum: INTEGER;
      a: ARRAY 5 OF INTEGER;
BEGIN
  a[0] := 10; a[1] := 20; a[2] := 30; a[3] := 40; a[4] := 50;
  Out.Int(a[0], 1); Out.Ln();
  Out.Int(a[1], 1); Out.Ln();
  Out.Int(a[2], 1); Out.Ln();
  sum := 0;
  i := 0;
  WHILE i < 5 DO
    sum := sum + a[i];
    i := i + 1
  END;
  Out.Int(sum, 1); Out.Ln()
END L2_Array.
