MODULE L5_SetIn;
  IMPORT Out;
  VAR s: SET; x: INTEGER;
BEGIN
  s := {1, 3, 5, 7};

  (* Constant IN: bit set *)
  IF 3 IN s THEN Out.Char("Y") ELSE Out.Char("N") END;
  Out.Ln();

  (* Constant IN: bit clear *)
  IF 2 IN s THEN Out.Char("Y") ELSE Out.Char("N") END;
  Out.Ln();

  (* Variable IN: bit set *)
  x := 5;
  IF x IN s THEN Out.Char("Y") ELSE Out.Char("N") END;
  Out.Ln();

  (* Variable IN: bit clear *)
  x := 4;
  IF x IN s THEN Out.Char("Y") ELSE Out.Char("N") END;
  Out.Ln();

  (* Bit 0 not set *)
  x := 0;
  IF x IN s THEN Out.Char("Y") ELSE Out.Char("N") END;
  Out.Ln();

  (* Bit 1 set *)
  x := 1;
  IF x IN s THEN Out.Char("Y") ELSE Out.Char("N") END;
  Out.Ln()
END L5_SetIn.
