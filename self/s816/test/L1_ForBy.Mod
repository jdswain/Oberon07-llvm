MODULE L1_ForBy;
  IMPORT Out;
  VAR i: INTEGER;
BEGIN
  (* Step by 2 *)
  FOR i := 0 TO 10 BY 2 DO
    Out.Int(i, 1); Out.Char(" ")
  END;
  Out.Ln();

  (* Step by 3 *)
  FOR i := 1 TO 12 BY 3 DO
    Out.Int(i, 1); Out.Char(" ")
  END;
  Out.Ln();

  (* Count down by -1 *)
  FOR i := 5 TO 1 BY -1 DO
    Out.Int(i, 1); Out.Char(" ")
  END;
  Out.Ln();

  (* Count down by -2 *)
  FOR i := 10 TO 0 BY -2 DO
    Out.Int(i, 1); Out.Char(" ")
  END;
  Out.Ln()
END L1_ForBy.
