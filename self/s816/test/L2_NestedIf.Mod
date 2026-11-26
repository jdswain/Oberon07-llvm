MODULE L2_NestedIf;
  IMPORT Out;

  PROCEDURE Classify(a, b: INTEGER): INTEGER;
    VAR r: INTEGER;
  BEGIN
    IF (a > 0) & (b > 0) THEN r := 1
    ELSIF (a > 0) & (b <= 0) THEN r := 2
    ELSIF (a <= 0) & (b > 0) THEN r := 3
    ELSE r := 4
    END;
    RETURN r
  END Classify;

BEGIN
  Out.Int(Classify(1, 1), 1); Out.Ln();
  Out.Int(Classify(1, -1), 1); Out.Ln();
  Out.Int(Classify(-1, 1), 1); Out.Ln();
  Out.Int(Classify(-1, -1), 1); Out.Ln()
END L2_NestedIf.
