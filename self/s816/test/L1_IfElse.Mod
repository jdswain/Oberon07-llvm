MODULE L1_IfElse;
  IMPORT Out;
  VAR x: INTEGER;
BEGIN
  (* Simple IF *)
  x := 5;
  IF x > 0 THEN Out.Char("P") END;
  Out.Ln();

  (* IF-ELSE *)
  x := -1;
  IF x > 0 THEN Out.Char("P")
  ELSE Out.Char("N")
  END;
  Out.Ln();

  (* IF-ELSIF-ELSE *)
  x := 0;
  IF x > 0 THEN Out.Char("P")
  ELSIF x < 0 THEN Out.Char("N")
  ELSE Out.Char("Z")
  END;
  Out.Ln();

  (* IF-ELSIF chain *)
  x := 3;
  IF x = 1 THEN Out.Char("A")
  ELSIF x = 2 THEN Out.Char("B")
  ELSIF x = 3 THEN Out.Char("C")
  ELSE Out.Char("?")
  END;
  Out.Ln()
END L1_IfElse.
