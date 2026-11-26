MODULE L18_B_IntDivZero; (* an INTEGER DIV by a variable 0 traps, 6, as a
   LONGINT one does *)
  IMPORT Out;
  VAR x, y: INTEGER;
BEGIN
  x := 100; y := 0; Out.Int(x, 4); Out.Ln;
  x := x DIV y; Out.Int(x, 7); Out.Ln
END L18_B_IntDivZero.
