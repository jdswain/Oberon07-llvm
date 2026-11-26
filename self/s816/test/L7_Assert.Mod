MODULE L7_Assert;
  IMPORT Out;
  VAR s: ARRAY 8 OF CHAR;
BEGIN
  ASSERT(TRUE);
  s := "PASS";
  Out.String(s); Out.Ln()
END L7_Assert.
