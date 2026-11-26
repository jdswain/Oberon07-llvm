MODULE L2_StringLiteral;
  IMPORT Out;
  VAR s: ARRAY 16 OF CHAR;
BEGIN
  s := "Hello";
  Out.String(s); Out.Ln();
  s := "World";
  Out.String(s); Out.Ln()
END L2_StringLiteral.
