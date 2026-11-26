MODULE L1_VarParams;
  IMPORT Out;
  VAR x, y: INTEGER;

  PROCEDURE Inc(VAR x: INTEGER);
  BEGIN
    x := x + 1
  END Inc;

  PROCEDURE Swap(VAR a, b: INTEGER);
    VAR t: INTEGER;
  BEGIN
    t := a; a := b; b := t
  END Swap;

BEGIN
  x := 10;
  Inc(x);
  Out.Int(x, 1); Out.Ln();

  x := 3; y := 7;
  Swap(x, y);
  Out.Int(x, 1); Out.Char(" "); Out.Int(y, 1); Out.Ln()
END L1_VarParams.
