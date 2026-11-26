MODULE L11_ManyLocals;
  IMPORT Out;

  PROCEDURE Test;
    VAR a, b, c, d, e, f, g, h, i, j: INTEGER;
  BEGIN
    a := 1; b := 2; c := 3; d := 4; e := 5;
    f := 6; g := 7; h := 8; i := 9; j := 10;
    Out.Int(a + b + c + d + e + f + g + h + i + j, 1); Out.Ln;
    (* Verify first and last survive *)
    Out.Int(a, 1); Out.Ln;
    Out.Int(j, 1); Out.Ln
  END Test;

BEGIN
  Test
END L11_ManyLocals.
