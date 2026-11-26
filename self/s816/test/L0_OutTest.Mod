MODULE L0_OutTest;
  IMPORT Out;

BEGIN
  Out.Char("H"); Out.Char("i"); Out.Ln();
  Out.Hex(0ABCDH); Out.Ln();
  Out.Bool(TRUE); Out.Bool(FALSE); Out.Ln()
END L0_OutTest.
