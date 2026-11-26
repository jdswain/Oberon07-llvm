MODULE L0_ForLoopRun;
  IMPORT Out;

  VAR i: INTEGER;

BEGIN
  (* Simple FOR loop counting up *)
  FOR i := 1 TO 5 DO
    Out.Int(i, 1); Out.Char(" ")
  END;
  Out.Ln();

  (* FOR loop with larger range *)
  FOR i := 0 TO 3 DO
    Out.Int(i * 10, 1); Out.Char(" ")
  END;
  Out.Ln()
END L0_ForLoopRun.
