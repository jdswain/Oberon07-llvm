MODULE L6_CaseChar;
  IMPORT Out;
  VAR ch: CHAR;
BEGIN
  ch := "B";
  CASE ch OF
    "A": Out.Int(1, 1); Out.Ln
  | "B": Out.Int(2, 1); Out.Ln
  | "C": Out.Int(3, 1); Out.Ln
  END;
  Out.Int(99, 1); Out.Ln
END L6_CaseChar.
