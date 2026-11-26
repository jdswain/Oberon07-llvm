MODULE L2_MultiArray;
  IMPORT Out;
  VAR a, b: ARRAY 3 OF INTEGER;
      i: INTEGER;
BEGIN
  a[0] := 5; a[1] := 10; a[2] := 15;
  i := 0;
  WHILE i < 3 DO
    b[i] := a[i];
    i := i + 1
  END;
  i := 0;
  WHILE i < 3 DO
    Out.Int(b[i], 1); Out.Ln();
    i := i + 1
  END
END L2_MultiArray.
