MODULE L18_A_ConstArrVar; (* the module's own constant array for a VAR parameter *)
  CONST Days = ARRAY OF INTEGER {31, 28, 31};
  PROCEDURE Leap(VAR d: ARRAY OF INTEGER);
  BEGIN d[1] := 29
  END Leap;
BEGIN Leap(Days)
END L18_A_ConstArrVar.
