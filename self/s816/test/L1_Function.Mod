MODULE L1_Function;
  IMPORT Out;

  PROCEDURE Double(x: INTEGER): INTEGER;
  BEGIN
    RETURN x * 2
  END Double;

  PROCEDURE Max(a, b: INTEGER): INTEGER;
    VAR result: INTEGER;
  BEGIN
    IF a > b THEN result := a
    ELSE result := b
    END;
    RETURN result
  END Max;

  PROCEDURE Square(x: INTEGER): INTEGER;
  BEGIN
    RETURN x * x
  END Square;

BEGIN
  Out.Int(Double(21), 1); Out.Ln();
  Out.Int(Max(3, 7), 1); Out.Ln();
  Out.Int(Max(9, 2), 1); Out.Ln();
  Out.Int(Square(5), 1); Out.Ln()
END L1_Function.
