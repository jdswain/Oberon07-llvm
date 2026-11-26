MODULE L5_SetDifference;
  IMPORT Out;
  VAR s1, s2, r: SET;
BEGIN
  (* Const - Const: {0..7} - {4..7} = {0..3} *)
  s1 := {0..7};
  s2 := {4..7};
  r := s1 - s2;
  Out.Hex(ORD(r)); Out.Ln();

  (* Var - Const *)
  s1 := {0..15};
  r := s1 - {0..7};
  Out.Hex(ORD(r)); Out.Ln();

  (* Var - Var *)
  s1 := {0, 1, 2, 3, 4};
  s2 := {1, 3};
  r := s1 - s2;
  Out.Hex(ORD(r)); Out.Ln()
END L5_SetDifference.
