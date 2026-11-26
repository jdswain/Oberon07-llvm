MODULE L6_CaseRange;
  IMPORT Out;
  VAR x: INTEGER;
BEGIN
  x := 7;
  CASE x OF
    1 .. 5: Out.Int(1, 1); Out.Ln
  | 6 .. 10: Out.Int(2, 1); Out.Ln
  | 11 .. 20: Out.Int(3, 1); Out.Ln
  END;
  Out.Int(99, 1); Out.Ln
END L6_CaseRange.
