MODULE L1_AddSub;
  IMPORT Out;
  VAR a, b, r: INTEGER;
BEGIN
  (* const + const *)
  Out.Int(3 + 4, 1); Out.Ln();
  (* var + const *)
  a := 10;
  r := a + 5;
  Out.Int(r, 1); Out.Ln();
  (* var + var *)
  a := 20; b := 30;
  r := a + b;
  Out.Int(r, 1); Out.Ln();
  (* const - const *)
  Out.Int(10 - 3, 1); Out.Ln();
  (* var - const *)
  a := 50;
  r := a - 8;
  Out.Int(r, 1); Out.Ln();
  (* var - var *)
  a := 100; b := 37;
  r := a - b;
  Out.Int(r, 1); Out.Ln()
END L1_AddSub.
