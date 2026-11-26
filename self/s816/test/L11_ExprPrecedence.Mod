MODULE L11_ExprPrecedence;
  IMPORT Out;
  VAR a, b, c: INTEGER;
BEGIN
  (* * binds tighter than + *)
  Out.Int(2 + 3 * 4, 1); Out.Ln;
  (* DIV binds tighter than - *)
  Out.Int(10 - 6 DIV 2, 1); Out.Ln;
  (* Parentheses override *)
  Out.Int((2 + 3) * 4, 1); Out.Ln;
  (* Mixed with variables *)
  a := 2; b := 3; c := 4;
  Out.Int(a + b * c, 1); Out.Ln;
  (* Unary minus *)
  Out.Int(-a + b, 1); Out.Ln;
  (* & binds tighter than OR *)
  IF TRUE OR FALSE & FALSE THEN
    Out.Int(1, 1); Out.Ln
  ELSE
    Out.Int(0, 1); Out.Ln
  END
END L11_ExprPrecedence.
