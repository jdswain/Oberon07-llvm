MODULE Arrs;

  CONST N = 8;

  VAR
    buf*: ARRAY N OF INTEGER;

  PROCEDURE Set*(i, v: INTEGER);
  BEGIN
    buf[i] := v
  END Set;

  PROCEDURE Get*(i: INTEGER): INTEGER;
  BEGIN
    RETURN buf[i]
  END Get;

  PROCEDURE Sum*(): INTEGER;
    VAR i, total: INTEGER;
  BEGIN
    total := 0;
    i := 0;
    WHILE i < N DO
      total := total + buf[i];
      i := i + 1
    END;
    RETURN total
  END Sum;

BEGIN
  Set(0, 10);
  Set(1, 20);
  Set(2, 30)
END Arrs.
