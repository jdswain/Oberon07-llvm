MODULE L2_TypeAlias;
  IMPORT Out;
  TYPE IntArray = ARRAY 4 OF INTEGER;
  VAR a: IntArray;
      i, sum: INTEGER;

  PROCEDURE Sum(VAR arr: ARRAY OF INTEGER): INTEGER;
    VAR i, s: INTEGER;
  BEGIN
    s := 0; i := 0;
    WHILE i < LEN(arr) DO
      s := s + arr[i];
      i := i + 1
    END;
    RETURN s
  END Sum;

BEGIN
  a[0] := 10; a[1] := 10; a[2] := 10; a[3] := 10;
  Out.Int(a[0], 1); Out.Ln();
  Out.Int(Sum(a), 1); Out.Ln()
END L2_TypeAlias.
