MODULE Mix;

  VAR data*: ARRAY 5 OF INTEGER;

  PROCEDURE SumOpen(VAR a: ARRAY OF INTEGER): INTEGER;
    VAR i, s: INTEGER;
  BEGIN
    s := 0;
    FOR i := 0 TO LEN(a) - 1 DO
      s := s + a[i]
    END;
    RETURN s
  END SumOpen;

  PROCEDURE TotalData*(): INTEGER;
  BEGIN
    RETURN SumOpen(data)
  END TotalData;

BEGIN
  data[0] := 10;
  data[1] := 20;
  data[2] := 30;
  data[3] := 40;
  data[4] := 50
END Mix.
