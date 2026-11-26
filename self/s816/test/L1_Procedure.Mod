MODULE L1_Procedure;
  IMPORT Out;

  PROCEDURE Greet;
  BEGIN
    Out.Char("H"); Out.Char("i"); Out.Ln()
  END Greet;

  PROCEDURE PrintNum;
  BEGIN
    Out.Int(42, 1); Out.Ln()
  END PrintNum;

BEGIN
  Greet;
  PrintNum;
  Greet
END L1_Procedure.
