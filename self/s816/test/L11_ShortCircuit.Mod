MODULE L11_ShortCircuit;
  IMPORT Out;
  VAR x: INTEGER;
BEGIN
  (* & short-circuits: left FALSE, right not evaluated *)
  x := 0;
  IF (x # 0) & (10 DIV x > 1) THEN
    Out.Int(1, 1); Out.Ln
  ELSE
    Out.Int(0, 1); Out.Ln
  END;
  (* OR short-circuits: left TRUE, right not evaluated *)
  x := 0;
  IF (x = 0) OR (10 DIV x > 1) THEN
    Out.Int(1, 1); Out.Ln
  ELSE
    Out.Int(0, 1); Out.Ln
  END;
  (* Normal case: both sides evaluated *)
  x := 5;
  IF (x # 0) & (10 DIV x > 1) THEN
    Out.Int(1, 1); Out.Ln
  ELSE
    Out.Int(0, 1); Out.Ln
  END
END L11_ShortCircuit.
