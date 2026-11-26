MODULE L6_CaseNested;
  IMPORT Out;

  PROCEDURE Test(x: INTEGER);
  BEGIN
    CASE x OF
      1: Out.Int(10, 1); Out.Ln
    | 2: Out.Int(20, 1); Out.Ln
    | 3: Out.Int(30, 1); Out.Ln
    ELSE Out.Int(0, 1); Out.Ln
    END
  END Test;

BEGIN
  Test(1);
  Test(3);
  Test(7);
  Out.Int(99, 1); Out.Ln
END L6_CaseNested.
