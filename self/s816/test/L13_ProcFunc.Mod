MODULE L13_ProcFunc;
  IMPORT Out;
  TYPE IntFunc = PROCEDURE(x: INTEGER): INTEGER;
  VAR f: IntFunc;

  PROCEDURE Square*(x: INTEGER): INTEGER;
  BEGIN RETURN x * x
  END Square;

  PROCEDURE Cube*(x: INTEGER): INTEGER;
  BEGIN RETURN x * x * x
  END Cube;
BEGIN
  f := Square; Out.Int(f(4), 0); Out.Ln;
  f := Cube; Out.Int(f(3), 0); Out.Ln
END L13_ProcFunc.
