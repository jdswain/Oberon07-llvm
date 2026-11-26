MODULE L1_CharType;
  IMPORT Out;
  VAR c: CHAR;
      x: INTEGER;
BEGIN
  c := "A";
  Out.Char(c); Out.Ln();
  (* ORD *)
  x := ORD(c);
  Out.Int(x, 1); Out.Ln();
  (* CHR *)
  c := CHR(66);
  Out.Char(c); Out.Ln();
  (* Round trip *)
  c := CHR(ORD("Z"));
  Out.Char(c); Out.Ln()
END L1_CharType.
