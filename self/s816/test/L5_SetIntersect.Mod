MODULE L5_SetIntersect;
  IMPORT Out;
  VAR s1, s2, r: SET;
BEGIN
  (* Const * Const *)
  s1 := {0, 1, 2, 3};
  s2 := {2, 3, 4, 5};
  r := s1 * s2;
  Out.Hex(ORD(r)); Out.Ln();

  (* Var * Const *)
  s1 := {0..7};
  r := s1 * {4..11};
  Out.Hex(ORD(r)); Out.Ln();

  (* Var * Var *)
  s1 := {1, 3, 5, 7};
  s2 := {0, 1, 2, 3};
  r := s1 * s2;
  Out.Hex(ORD(r)); Out.Ln()
END L5_SetIntersect.
