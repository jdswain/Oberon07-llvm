MODULE L9_MultiImport;
  IMPORT Out, L9_Lib, L9_Base;
BEGIN
  Out.Int(L9_Lib.Add(L9_Base.baseVal, L9_Lib.count), 1); Out.Ln();
  Out.Int(L9_Base.Double(L9_Lib.count), 1); Out.Ln()
END L9_MultiImport.
