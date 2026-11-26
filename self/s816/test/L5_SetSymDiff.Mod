MODULE L5_SetSymDiff;
  IMPORT Out;
  VAR s1, s2, r: SET;
BEGIN
  (* Const / Const *)
  s1 := {0, 1, 2};
  s2 := {1, 2, 3};
  r := s1 / s2;
  Out.Hex(ORD(r)); Out.Ln();

  (* Var / Const *)
  s1 := {0..7};
  r := s1 / {4..11};
  Out.Hex(ORD(r)); Out.Ln();

  (* Var / Var *)
  s1 := {0, 2, 4};
  s2 := {0, 1, 2};
  r := s1 / s2;
  Out.Hex(ORD(r)); Out.Ln()
END L5_SetSymDiff.
