MODULE L11_EmptyLoop;
  IMPORT Out;
  VAR x, count: INTEGER;
BEGIN
  (* FOR with start > end: zero iterations *)
  count := 0;
  FOR x := 5 TO 1 DO
    count := count + 1
  END;
  Out.Int(count, 1); Out.Ln;
  (* WHILE with initially FALSE condition *)
  count := 0;
  x := 0;
  WHILE x > 0 DO
    count := count + 1;
    x := x - 1
  END;
  Out.Int(count, 1); Out.Ln;
  (* REPEAT always executes at least once *)
  count := 0;
  REPEAT
    count := count + 1
  UNTIL TRUE;
  Out.Int(count, 1); Out.Ln
END L11_EmptyLoop.
