MODULE L9_VarParam;
  IMPORT Out, L9_Lib;
  VAR x: INTEGER;
BEGIN
  x := 10;
  L9_Lib.Inc(x);
  Out.Int(x, 1); Out.Ln();
  L9_Lib.Inc(x);
  Out.Int(x, 1); Out.Ln()
END L9_VarParam.
