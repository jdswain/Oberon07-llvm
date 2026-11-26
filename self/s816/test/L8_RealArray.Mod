MODULE L8_RealArray;
  IMPORT Out;
  VAR arr: ARRAY 3 OF REAL;
    i: INTEGER;
BEGIN
  arr[0] := 1.0;
  arr[1] := 2.0;
  arr[2] := 3.0;
  FOR i := 0 TO 2 DO
    Out.Int(FLOOR(arr[i]), 1); Out.Ln()
  END
END L8_RealArray.
