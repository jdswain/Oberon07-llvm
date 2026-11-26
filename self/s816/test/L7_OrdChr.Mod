MODULE L7_OrdChr;
  IMPORT Out;
  VAR c: CHAR;
      i: INTEGER;
BEGIN
  c := "A";
  Out.Int(ORD(c), 1); Out.Ln();
  i := 48;
  Out.Char(CHR(i)); Out.Ln();
  c := "Z";
  Out.Char(CHR(ORD(c))); Out.Ln()
END L7_OrdChr.
