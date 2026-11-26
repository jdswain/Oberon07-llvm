MODULE L18_A_ConstVarPar; (* a constant for a VAR parameter *)
  VAR n: INTEGER;
  PROCEDURE Swap(VAR a, b: INTEGER);
    VAR t: INTEGER;
  BEGIN t := a; a := b; b := t
  END Swap;
BEGIN n := 1; Swap(3, n)
END L18_A_ConstVarPar.
