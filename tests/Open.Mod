MODULE Open;

  PROCEDURE Sum*(VAR a: ARRAY OF INTEGER): INTEGER;
    VAR i, s: INTEGER;
  BEGIN
    s := 0;
    FOR i := 0 TO LEN(a) - 1 DO
      s := s + a[i]
    END;
    RETURN s
  END Sum;

  PROCEDURE Fill*(VAR a: ARRAY OF INTEGER; v: INTEGER);
    VAR i: INTEGER;
  BEGIN
    FOR i := 0 TO LEN(a) - 1 DO
      a[i] := v
    END
  END Fill;

  PROCEDURE Length*(VAR a: ARRAY OF INTEGER): INTEGER;
  BEGIN
    RETURN LEN(a)
  END Length;

END Open.
