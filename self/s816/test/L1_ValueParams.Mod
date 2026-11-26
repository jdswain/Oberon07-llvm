MODULE L1_ValueParams;
  IMPORT Out;

  PROCEDURE PrintInt(x: INTEGER);
  BEGIN
    Out.Int(x, 1); Out.Ln()
  END PrintInt;

  PROCEDURE PrintChar(c: CHAR);
  BEGIN
    Out.Char(c); Out.Ln()
  END PrintChar;

  PROCEDURE PrintBool(b: BOOLEAN);
  BEGIN
    Out.Bool(b); Out.Ln()
  END PrintBool;

  PROCEDURE Add(a, b: INTEGER);
  BEGIN
    Out.Int(a + b, 1); Out.Ln()
  END Add;

BEGIN
  PrintInt(42);
  PrintChar("X");
  PrintBool(TRUE);
  PrintBool(FALSE);
  Add(17, 25)
END L1_ValueParams.
