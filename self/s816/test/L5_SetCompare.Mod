MODULE L5_SetCompare;
  IMPORT Out;
  VAR s1, s2: SET;
BEGIN
  s1 := {1, 3, 5};
  s2 := {1, 3, 5};

  (* Equal *)
  IF s1 = s2 THEN Out.Char("Y") ELSE Out.Char("N") END;
  Out.Ln();

  (* Not equal *)
  s2 := {1, 3, 7};
  IF s1 # s2 THEN Out.Char("Y") ELSE Out.Char("N") END;
  Out.Ln();

  (* Equal after reassign *)
  s2 := s1;
  IF s1 = s2 THEN Out.Char("Y") ELSE Out.Char("N") END;
  Out.Ln();

  (* Empty sets equal *)
  s1 := {};
  s2 := {};
  IF s1 = s2 THEN Out.Char("Y") ELSE Out.Char("N") END;
  Out.Ln()
END L5_SetCompare.
