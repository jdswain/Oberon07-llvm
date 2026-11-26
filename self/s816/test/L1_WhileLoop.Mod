MODULE L1_WhileLoop;
  IMPORT Out;
  VAR i, sum: INTEGER;
BEGIN
  (* Count up *)
  i := 1;
  WHILE i <= 5 DO
    Out.Int(i, 1); Out.Char(" ");
    i := i + 1
  END;
  Out.Ln();

  (* Sum 1..10 *)
  i := 1; sum := 0;
  WHILE i <= 10 DO
    sum := sum + i;
    i := i + 1
  END;
  Out.Int(sum, 1); Out.Ln();

  (* Zero iterations *)
  i := 10;
  WHILE i < 5 DO
    Out.Char("X");
    i := i + 1
  END;
  Out.Char("."); Out.Ln()
END L1_WhileLoop.
