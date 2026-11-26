MODULE L1_ForLoop;
  IMPORT Out;
  VAR i, sum: INTEGER;
BEGIN
  (* Simple count up *)
  FOR i := 1 TO 5 DO
    Out.Int(i, 1); Out.Char(" ")
  END;
  Out.Ln();

  (* Sum *)
  sum := 0;
  FOR i := 1 TO 10 DO
    sum := sum + i
  END;
  Out.Int(sum, 1); Out.Ln();

  (* Single iteration *)
  FOR i := 7 TO 7 DO
    Out.Int(i, 1)
  END;
  Out.Ln()
END L1_ForLoop.
