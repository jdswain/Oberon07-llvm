MODULE L18_B_IntDivNeg; (* INTEGER DIV and MOD by a variable divisor
   that is negative: the quotient rounded down, the remainder of the
   divisor's sign *)
  IMPORT Out;
  VAR x, y, i, j: INTEGER; a: ARRAY 6 OF INTEGER;

  PROCEDURE D(x, y: INTEGER);
  BEGIN Out.Int(x DIV y, 7); Out.Int(x MOD y, 7)
  END D;

BEGIN
  a[0] := 7; a[1] := -7; a[2] := 6; a[3] := -6; a[4] := 0; a[5] := 32767;
  FOR i := 0 TO 5 DO
    FOR j := 0 TO 3 DO D(a[i], a[j]) END; Out.Ln
  END;
  D(-32768, -32768); D(-1, -32768); D(-32768, -1); D(32767, -32768); Out.Ln;
  D(-32768, 32767); D(100, 3); D(-100, 3); D(100, -3); Out.Ln;
  x := 7; y := -2; x := x DIV y; Out.Int(x, 7); x := 7; x := x MOD y; Out.Int(x, 7);
  Out.Int(100 DIV 7, 7); Out.Int(-100 DIV 7, 7); Out.Int(-100 MOD 7, 7); Out.Int(-100 MOD 8, 7); Out.Ln
END L18_B_IntDivNeg.
