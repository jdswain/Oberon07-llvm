MODULE StringCallTest;
  IMPORT Out;
  VAR s: ARRAY 32 OF CHAR;
BEGIN
  s := "Hello";
  Out.String(s); Out.Ln
END StringCallTest.
