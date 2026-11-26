MODULE L1_Recursion;
  IMPORT Out;

  PROCEDURE Fact(n: INTEGER): INTEGER;
    VAR result: INTEGER;
  BEGIN
    IF n <= 1 THEN result := 1
    ELSE result := n * Fact(n - 1)
    END;
    RETURN result
  END Fact;

BEGIN
  Out.Int(Fact(1), 1); Out.Ln();
  Out.Int(Fact(5), 1); Out.Ln();
  Out.Int(Fact(7), 1); Out.Ln()
END L1_Recursion.
