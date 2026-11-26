MODULE L9_Lib;

  VAR version*, count*: INTEGER;

  PROCEDURE Add*(a, b: INTEGER): INTEGER;
  BEGIN
    RETURN a + b
  END Add;

  PROCEDURE Negate*(x: INTEGER): INTEGER;
  BEGIN
    RETURN -x
  END Negate;

  PROCEDURE Max*(a, b: INTEGER): INTEGER;
    VAR result: INTEGER;
  BEGIN
    IF a > b THEN result := a
    ELSE result := b
    END;
    RETURN result
  END Max;

  PROCEDURE Inc*(VAR x: INTEGER);
  BEGIN
    x := x + 1
  END Inc;

BEGIN
  version := 1;
  count := 42
END L9_Lib.
