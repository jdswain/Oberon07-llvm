MODULE L1_NestedProc;
  IMPORT Out;

  PROCEDURE Outer;

    PROCEDURE Inner;
    BEGIN
      Out.Char("I"); Out.Ln()
    END Inner;

  BEGIN
    Out.Char("O"); Out.Ln();
    Inner
  END Outer;

BEGIN
  Outer
END L1_NestedProc.
