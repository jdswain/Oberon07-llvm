MODULE L11_LargeArray;
  IMPORT Out;
  VAR a: ARRAY 100 OF INTEGER;
      i, sum: INTEGER;
BEGIN
  FOR i := 0 TO 99 DO
    a[i] := i + 1
  END;
  sum := 0;
  FOR i := 0 TO 99 DO
    sum := sum + a[i]
  END;
  Out.Int(sum, 1); Out.Ln;
  Out.Int(a[0], 1); Out.Ln;
  Out.Int(a[99], 1); Out.Ln
END L11_LargeArray.
