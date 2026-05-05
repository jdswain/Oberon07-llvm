MODULE Branch;

  PROCEDURE Max*(a, b: INTEGER): INTEGER;
    VAR r: INTEGER;
  BEGIN
    IF a > b THEN r := a ELSE r := b END;
    RETURN r
  END Max;

  PROCEDURE Sign*(x: INTEGER): INTEGER;
    VAR r: INTEGER;
  BEGIN
    IF x < 0 THEN r := -1
    ELSIF x = 0 THEN r := 0
    ELSE r := 1
    END;
    RETURN r
  END Sign;

END Branch.
