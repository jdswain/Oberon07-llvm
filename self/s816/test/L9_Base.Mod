MODULE L9_Base;
  IMPORT Out;

  VAR baseVal*: INTEGER;

  PROCEDURE Double*(x: INTEGER): INTEGER;
  BEGIN
    RETURN x + x
  END Double;

BEGIN
  baseVal := 100;
  Out.Int(1, 1); Out.Ln()
END L9_Base.
