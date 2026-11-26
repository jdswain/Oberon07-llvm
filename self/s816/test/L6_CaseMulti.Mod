MODULE L6_CaseMulti;
  IMPORT Out;
  VAR x: INTEGER;
BEGIN
  x := 5;
  CASE x OF
    1, 3, 5: Out.Int(1, 1); Out.Ln
  | 2, 4, 6: Out.Int(2, 1); Out.Ln
  END;
  Out.Int(99, 1); Out.Ln
END L6_CaseMulti.
