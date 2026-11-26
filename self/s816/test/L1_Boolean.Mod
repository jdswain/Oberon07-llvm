MODULE L1_Boolean;
  IMPORT Out;
  VAR a, b: BOOLEAN;
BEGIN
  a := TRUE; b := FALSE;
  (* AND *)
  Out.Bool(a & a); Out.Bool(a & b); Out.Bool(b & b); Out.Ln();
  (* OR *)
  Out.Bool(a OR a); Out.Bool(a OR b); Out.Bool(b OR b); Out.Ln();
  (* NOT *)
  Out.Bool(~a); Out.Bool(~b); Out.Ln();
  (* Short circuit: FALSE & (side-effect) should not evaluate RHS *)
  (* We test this by using a comparison that would be true *)
  Out.Bool(FALSE & (1 > 0)); Out.Ln();
  (* Short circuit: TRUE OR (side-effect) should not evaluate RHS *)
  Out.Bool(TRUE OR (1 < 0)); Out.Ln()
END L1_Boolean.
