MODULE L1_Constants;
  IMPORT Out;
  CONST
    N = 100;
    H = 0ABH;
    C = "Z";
BEGIN
  Out.Int(N, 1); Out.Ln();
  Out.Hex(H); Out.Ln();
  Out.Char(C); Out.Ln()
END L1_Constants.
