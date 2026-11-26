MODULE L18_A_ManyDigits; (* a number of more than 16 digits: reported, then on *)
  IMPORT Out;
  CONST Big = 12345678901234567; Hex = 0123456789ABCDEF0H;
  VAR i: INTEGER;
BEGIN i := 1; Out.Int(i, 0); Out.Ln
END L18_A_ManyDigits.
