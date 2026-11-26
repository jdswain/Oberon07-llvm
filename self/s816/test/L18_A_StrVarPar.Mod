MODULE L18_A_StrVarPar; (* a string for a VAR ARRAY OF CHAR parameter *)
  PROCEDURE Fill(VAR s: ARRAY OF CHAR);
  BEGIN s[0] := "x"
  END Fill;
BEGIN Fill("abc")
END L18_A_StrVarPar.
