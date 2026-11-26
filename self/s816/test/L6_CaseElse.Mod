MODULE L6_CaseElse;
  IMPORT Out;
  VAR x: INTEGER;
BEGIN
  x := 99;
  CASE x OF
    1: Out.Int(10, 1); Out.Ln
  | 2: Out.Int(20, 1); Out.Ln
  ELSE Out.Int(0, 1); Out.Ln
  END;
  Out.Int(77, 1); Out.Ln
END L6_CaseElse.
