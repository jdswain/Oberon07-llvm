MODULE L0_RuntimeTest;
  IMPORT Out, Runtime;

  VAR r: INTEGER;

BEGIN
  r := Runtime.Mul(6, 7);
  Out.Hex(r); Out.Ln();
  r := Runtime.Mul(100, 200);
  Out.Hex(r); Out.Ln();
  r := Runtime.Mul(-3, 5);
  Out.Hex(r); Out.Ln();
  r := Runtime.Div(42, 6);
  Out.Hex(r); Out.Ln();
  r := Runtime.Div(100, 7);
  Out.Hex(r); Out.Ln();
  r := Runtime.Mod(100, 7);
  Out.Hex(r); Out.Ln()
END L0_RuntimeTest.
