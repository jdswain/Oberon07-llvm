MODULE L1_Divide;
  IMPORT Out;
  VAR a, b, r: INTEGER;
BEGIN
  (* const DIV const *)
  Out.Int(42 DIV 6, 1); Out.Ln();
  (* var DIV const *)
  a := 100;
  r := a DIV 7;
  Out.Int(r, 1); Out.Ln();
  (* var DIV var *)
  a := 100; b := 10;
  r := a DIV b;
  Out.Int(r, 1); Out.Ln();
  (* power-of-2 DIV *)
  a := 100;
  r := a DIV 4;
  Out.Int(r, 1); Out.Ln();
  (* DIV with exact result *)
  a := 48; b := 8;
  r := a DIV b;
  Out.Int(r, 1); Out.Ln()
END L1_Divide.
