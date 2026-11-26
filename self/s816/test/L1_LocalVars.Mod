MODULE L1_LocalVars;
  IMPORT Out;

  VAR g: INTEGER;

  PROCEDURE Compute;
    VAR a, b, c: INTEGER;
  BEGIN
    a := 10;
    b := 20;
    c := a + b;
    Out.Int(c, 1); Out.Ln()
  END Compute;

  PROCEDURE NoConflict;
    VAR a: INTEGER;
  BEGIN
    a := 99;
    Out.Int(a, 1); Out.Ln()
  END NoConflict;

BEGIN
  g := 5;
  Compute;
  NoConflict;
  (* Global should be unchanged *)
  Out.Int(g, 1); Out.Ln()
END L1_LocalVars.
