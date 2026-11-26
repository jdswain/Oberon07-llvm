MODULE L7_IncDec;
  IMPORT Out;
  VAR g: INTEGER;

  PROCEDURE TestLocal;
    VAR x: INTEGER;
  BEGIN
    x := 10;
    INC(x);
    Out.Int(x, 1); Out.Ln();
    DEC(x);
    Out.Int(x, 1); Out.Ln();
    INC(x, 5);
    Out.Int(x, 1); Out.Ln();
    DEC(x, 3);
    Out.Int(x, 1); Out.Ln()
  END TestLocal;

BEGIN
  g := 100;
  INC(g);
  Out.Int(g, 1); Out.Ln();
  DEC(g);
  Out.Int(g, 1); Out.Ln();
  INC(g, 10);
  Out.Int(g, 1); Out.Ln();
  DEC(g, 50);
  Out.Int(g, 1); Out.Ln();
  TestLocal
END L7_IncDec.
