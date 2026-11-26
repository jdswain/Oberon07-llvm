MODULE L1_RepeatLoop;
  IMPORT Out;
  VAR i, n: INTEGER;
BEGIN
  (* Count down *)
  i := 5;
  REPEAT
    Out.Int(i, 1); Out.Char(" ");
    i := i - 1
  UNTIL i = 0;
  Out.Ln();

  (* Find number of digits *)
  n := 12345; i := 0;
  REPEAT
    n := n DIV 10;
    i := i + 1
  UNTIL n = 0;
  Out.Int(i, 1); Out.Ln()
END L1_RepeatLoop.
