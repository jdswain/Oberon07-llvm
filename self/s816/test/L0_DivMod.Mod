MODULE L0_DivMod;
  IMPORT Out;

  VAR a, b, r: INTEGER;

BEGIN
  (* Test DIV with variables *)
  a := 42; b := 6;
  r := a DIV b;
  Out.Int(r, 1); Out.Ln();

  (* Test MOD with variables *)
  a := 100; b := 7;
  r := a MOD b;
  Out.Int(r, 1); Out.Ln();

  (* Test DIV with constant divisor (non-power-of-2) *)
  a := 100;
  r := a DIV 7;
  Out.Int(r, 1); Out.Ln();

  (* Test MOD with constant divisor (non-power-of-2) *)
  a := 100;
  r := a MOD 7;
  Out.Int(r, 1); Out.Ln();

  (* Test MOD with power-of-2 *)
  a := 100;
  r := a MOD 8;
  Out.Int(r, 1); Out.Ln();

  (* Test DIV with power-of-2 *)
  a := 100;
  r := a DIV 4;
  Out.Int(r, 1); Out.Ln()
END L0_DivMod.
