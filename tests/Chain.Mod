MODULE Chain;

  PROCEDURE All*(a, b, c: BOOLEAN): BOOLEAN;
    VAR r: BOOLEAN;
  BEGIN
    r := a & b & c;
    RETURN r
  END All;

  PROCEDURE Any*(a, b, c: BOOLEAN): BOOLEAN;
    VAR r: BOOLEAN;
  BEGIN
    r := a OR b OR c;
    RETURN r
  END Any;

  PROCEDURE Mix*(a, b, c: BOOLEAN): BOOLEAN;
    VAR r: BOOLEAN;
  BEGIN
    r := (a OR b) & c;
    RETURN r
  END Mix;

END Chain.
