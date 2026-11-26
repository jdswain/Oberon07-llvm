MODULE L2_ArrayParam;
  IMPORT Out;
  VAR arr: ARRAY 4 OF INTEGER;
      i: INTEGER;

  PROCEDURE Fill(VAR a: ARRAY OF INTEGER);
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE i < LEN(a) DO
      a[i] := i * 2;
      i := i + 1
    END
  END Fill;

BEGIN
  Fill(arr);
  i := 0;
  WHILE i < 4 DO
    Out.Int(arr[i], 1); Out.Ln();
    i := i + 1
  END
END L2_ArrayParam.
