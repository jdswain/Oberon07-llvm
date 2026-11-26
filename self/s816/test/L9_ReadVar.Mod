MODULE L9_ReadVar;
  IMPORT Out, L9_Lib;
BEGIN
  Out.Int(L9_Lib.version, 1); Out.Ln();
  Out.Int(L9_Lib.count, 1); Out.Ln()
END L9_ReadVar.
