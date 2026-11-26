MODULE L11_OpenStrAssign;
  IMPORT Out;

  VAR a: ARRAY 20 OF CHAR; b: ARRAY 4 OF CHAR; i: INTEGER;

  (* strings assigned to an open array VAR parameter, after compares that
     leave the carry set and clear: the length checked, not the carry *)
  PROCEDURE Set(VAR s: ARRAY OF CHAR; k: INTEGER);
  BEGIN
    IF k > 5 THEN s := "big" ELSIF k >= 0 THEN s := "General" ELSE s := "" END
  END Set;

BEGIN
  Set(a, 9); Out.String(a); Out.Ln;
  Set(a, 1); Out.String(a); Out.Ln;
  i := -1; Set(a, i); Out.Int(ORD(a[0]), 0); Out.Ln;
  Set(b, 9); Out.String(b); Out.Ln
END L11_OpenStrAssign.
