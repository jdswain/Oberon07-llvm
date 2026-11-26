MODULE L11_LenIndexed;
  (* LEN of a fixed array reached through an index (a field of an element):
     the designator's registers are freed, so a function's result is still
     where its caller looks for it. *)
  IMPORT Out;
  TYPE R = RECORD n: INTEGER; name: ARRAY 16 OF CHAR END;
  VAR a: ARRAY 4 OF R; q: INTEGER;
  PROCEDURE F(): INTEGER;
    VAR i, p: INTEGER;
  BEGIN p := 1; i := 3;
    IF i < LEN(a[p].name) - 1 THEN i := 4 END;
    RETURN p * 100 + i
  END F;
  PROCEDURE G(s: ARRAY OF CHAR): INTEGER;
    VAR i, p: INTEGER;
  BEGIN p := 2; i := 0;
    WHILE (i < LEN(a[p].name) - 1) & (i < LEN(s)) & (s[i] # 0X) DO a[p].name[i] := s[i]; INC(i) END;
    a[p].name[i] := 0X;
    RETURN p
  END G;
BEGIN
  Out.Int(F(), 0); Out.Ln;            (* 104 *)
  q := G("idle"); Out.Int(q, 0); Out.Char(" "); Out.String(a[2].name); Out.Ln;   (* 2 idle *)
  Out.Int(LEN(a[q].name) + LEN(a), 0); Out.Ln    (* 20 *)
END L11_LenIndexed.
