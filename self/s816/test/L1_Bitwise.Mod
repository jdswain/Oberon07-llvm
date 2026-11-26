MODULE L1_Bitwise;
  IMPORT Out;
  VAR a, b, r: INTEGER;
BEGIN
  a := 0FFH; b := 0F0H;
  (* AND *)
  r := AND(a, b);
  Out.Hex(r); Out.Ln();
  (* OR *)
  r := ORA(a, 0FH);
  Out.Hex(r); Out.Ln();
  (* XOR *)
  r := EOR(0AAH, 055H);
  Out.Hex(r); Out.Ln();
  (* AND with mask *)
  a := 1234H;
  r := AND(a, 00FFH);
  Out.Hex(r); Out.Ln()
END L1_Bitwise.
