MODULE L1_Multiply;
  IMPORT Out;
  VAR a, b, r: INTEGER;
BEGIN
  (* const * const *)
  Out.Int(6 * 7, 1); Out.Ln();
  (* var * const *)
  a := 12;
  r := a * 5;
  Out.Int(r, 1); Out.Ln();
  (* power-of-2 multiply *)
  a := 25;
  r := a * 4;
  Out.Int(r, 1); Out.Ln();
  (* var * var *)
  a := 8; b := 9;
  r := a * b;
  Out.Int(r, 1); Out.Ln();
  (* multiply by negative *)
  a := 10;
  r := a * (-3);
  Out.Int(r, 1); Out.Ln();
  (* multiply by zero *)
  a := 99;
  r := a * 0;
  Out.Int(r, 1); Out.Ln()
END L1_Multiply.
