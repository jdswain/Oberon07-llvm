MODULE L1_Negate;
  IMPORT Out;
  VAR x: INTEGER;
BEGIN
  (* Negate positive *)
  x := 42;
  Out.Int(-x, 1); Out.Ln();
  (* Negate negative *)
  x := -7;
  Out.Int(-x, 1); Out.Ln();
  (* Negate zero *)
  x := 0;
  Out.Int(-x, 1); Out.Ln();
  (* Negate constant *)
  Out.Int(-100, 1); Out.Ln()
END L1_Negate.
