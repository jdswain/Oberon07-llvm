MODULE L8_RealParam;
  IMPORT Out;
  VAR a: REAL;

  PROCEDURE Show(x: REAL);
  BEGIN
    Out.Int(FLOOR(x), 1); Out.Ln()
  END Show;

  PROCEDURE Add(VAR x: REAL; y: REAL);
  BEGIN
    x := x + y
  END Add;

BEGIN
  a := 3.0;
  Show(a);
  Add(a, 4.0);
  Show(a)
END L8_RealParam.
