MODULE L11_ConstCond;
(* Constant conditions: IF TRUE, ELSIF TRUE, WHILE TRUE, TRUE & b,
   FALSE OR b, and their values. A branch that is never taken emits
   nothing; each follows a call to another module, whose operand the
   jump chain's fixup once overwrote (the loader then reported a JSL to
   a bad export). Forever is never called, but the loader resolves its
   calls too. *)
  IMPORT Out;

  VAR b, c: BOOLEAN; i: INTEGER;

  PROCEDURE Forever;
  BEGIN
    Out.String("never"); Out.Ln;
    WHILE TRUE DO Out.Int(i, 0); INC(i) END
  END Forever;

  PROCEDURE Show(s: ARRAY OF CHAR; x: BOOLEAN);
  BEGIN Out.String(s); IF x THEN Out.String(" T") ELSE Out.String(" F") END; Out.Ln
  END Show;

BEGIN
  b := TRUE; c := FALSE; i := 0;
  Out.String("if"); IF TRUE THEN Out.String(" then") END; Out.Ln;
  Out.String("elsif"); IF c THEN Out.String(" no") ELSIF TRUE THEN Out.String(" yes") END; Out.Ln;
  Out.String("and"); IF TRUE & b THEN Out.String(" yes") END; Out.Ln;
  Out.String("and f"); IF TRUE & c THEN Out.String(" no") ELSE Out.String(" else") END; Out.Ln;
  Out.String("or"); IF FALSE OR b THEN Out.String(" yes") END; Out.Ln;
  Out.String("or f"); IF FALSE OR c THEN Out.String(" no") ELSE Out.String(" else") END; Out.Ln;
  Out.String("while");
  WHILE i < 3 DO Out.String(" "); Out.Int(i, 0); INC(i) ELSIF FALSE DO Out.String(" no") END; Out.Ln;
  Out.Int(i, 0); Show(" T&b", TRUE & b);
  Out.Int(i, 0); Show(" T&c", TRUE & c);
  Out.Int(i, 0); Show(" F OR b", FALSE OR b);
  Out.Int(i, 0); Show(" F OR c", FALSE OR c);
  Out.Int(i, 0); c := TRUE & b; Show(" c", c);
  Out.String("done"); Out.Ln
END L11_ConstCond.
