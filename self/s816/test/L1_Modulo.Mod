MODULE L1_Modulo;
  IMPORT Out;
  VAR a, b, r: INTEGER;
BEGIN
  (* const MOD const *)
  Out.Int(17 MOD 5, 1); Out.Ln();
  (* var MOD const *)
  a := 100;
  r := a MOD 7;
  Out.Int(r, 1); Out.Ln();
  (* var MOD var *)
  a := 29; b := 6;
  r := a MOD b;
  Out.Int(r, 1); Out.Ln();
  (* power-of-2 MOD *)
  a := 100;
  r := a MOD 8;
  Out.Int(r, 1); Out.Ln();
  (* MOD with zero remainder *)
  a := 24; b := 6;
  r := a MOD b;
  Out.Int(r, 1); Out.Ln()
END L1_Modulo.
