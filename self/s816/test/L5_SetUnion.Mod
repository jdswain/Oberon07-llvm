MODULE L5_SetUnion;
  IMPORT Out;
  VAR s1, s2, r: SET;
BEGIN
  (* Const + Const *)
  s1 := {0, 1, 2};
  s2 := {2, 3, 4};
  r := s1 + s2;
  Out.Hex(ORD(r)); Out.Ln();

  (* Var + Const *)
  s1 := {0, 4, 8};
  r := s1 + {1, 5, 9};
  Out.Hex(ORD(r)); Out.Ln();

  (* Var + Var *)
  s1 := {0, 2};
  s2 := {1, 3};
  r := s1 + s2;
  Out.Hex(ORD(r)); Out.Ln()
END L5_SetUnion.
