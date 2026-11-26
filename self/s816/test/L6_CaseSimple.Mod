MODULE L6_CaseSimple;
  IMPORT Out;
  VAR x: INTEGER;
BEGIN
  x := 2;
  CASE x OF
    1: Out.Int(10, 1); Out.Ln
  | 2: Out.Int(20, 1); Out.Ln
  | 3: Out.Int(30, 1); Out.Ln
  END;
  Out.Int(99, 1); Out.Ln
END L6_CaseSimple.
