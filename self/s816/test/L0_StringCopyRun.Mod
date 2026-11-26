MODULE L0_StringCopyRun;
  IMPORT Out;

  VAR s: ARRAY 20 OF CHAR;

BEGIN
  s := "Hello";
  Out.String(s); Out.Ln()
END L0_StringCopyRun.
