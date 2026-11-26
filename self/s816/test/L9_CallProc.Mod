MODULE L9_CallProc;
  IMPORT Out, L9_Lib;
BEGIN
  Out.Int(L9_Lib.Add(3, 4), 1); Out.Ln();
  Out.Int(L9_Lib.Negate(42), 1); Out.Ln();
  Out.Int(L9_Lib.Max(10, 20), 1); Out.Ln();
  Out.Int(L9_Lib.Max(20, 10), 1); Out.Ln()
END L9_CallProc.
