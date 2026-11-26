MODULE L7_Len;
  IMPORT Out;
  VAR a: ARRAY 5 OF INTEGER;

  PROCEDURE PrintLen(a: ARRAY OF INTEGER);
  BEGIN
    Out.Int(LEN(a), 1); Out.Ln()
  END PrintLen;

BEGIN
  Out.Int(LEN(a), 1); Out.Ln();
  PrintLen(a)
END L7_Len.
