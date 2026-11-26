MODULE L8_RealOutput;
  IMPORT Out;

  PROCEDURE Test;
  BEGIN
    Out.Real(3.14159, 14); Out.Ln;
    Out.Real(-2.5, 14); Out.Ln;
    Out.Real(100.0, 14); Out.Ln;
    Out.Real(0.5, 14); Out.Ln;
    Out.Real(0.0, 14); Out.Ln;
    Out.Real(1.0, 14); Out.Ln;
    Out.Real(-0.001, 14); Out.Ln
  END Test;

BEGIN
  Test
END L8_RealOutput.
