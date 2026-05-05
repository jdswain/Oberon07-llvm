MODULE Reals;

  PROCEDURE Add*(a, b: REAL): REAL;
  BEGIN RETURN a + b END Add;

  PROCEDURE Sub*(a, b: REAL): REAL;
  BEGIN RETURN a - b END Sub;

  PROCEDURE Mul*(a, b: REAL): REAL;
  BEGIN RETURN a * b END Mul;

  PROCEDURE Div*(a, b: REAL): REAL;
  BEGIN RETURN a / b END Div;

  PROCEDURE Neg*(x: REAL): REAL;
  BEGIN RETURN -x END Neg;

  PROCEDURE Cmp*(a, b: REAL): INTEGER;
    VAR r: INTEGER;
  BEGIN
    IF a < b THEN r := -1
    ELSIF a > b THEN r := 1
    ELSE r := 0
    END;
    RETURN r
  END Cmp;

  PROCEDURE FromInt*(n: INTEGER): REAL;
  BEGIN
    RETURN FLT(n)
  END FromInt;

  PROCEDURE ToInt*(x: REAL): INTEGER;
  BEGIN
    RETURN FLOOR(x)
  END ToInt;

  (* A small loop to exercise REAL accumulation. *)
  PROCEDURE SumReciprocals*(n: INTEGER): REAL;
    VAR i: INTEGER; s: REAL;
  BEGIN
    s := 0.0;
    FOR i := 1 TO n DO
      s := s + 1.0 / FLT(i)
    END;
    RETURN s
  END SumReciprocals;

END Reals.
