MODULE L9_ImportStr; (* string constants imported: passed to an open
   array, assigned, compared with an array (either side), given to Out.String; their lengths *)
  IMPORT L9_StrLib, Out;
  VAR t: ARRAY 48 OF CHAR;

  PROCEDURE Show(s: ARRAY OF CHAR);
  BEGIN Out.Char("["); Out.String(s); Out.String("] len "); Out.Int(LEN(s), 0); Out.Ln
  END Show;

BEGIN
  Show(L9_StrLib.S); Show(L9_StrLib.Empty); Show(L9_StrLib.Long);
  t := L9_StrLib.S; Show(t);
  Out.String("direct "); Out.String(L9_StrLib.S); Out.Ln;
  IF t = L9_StrLib.S THEN Out.String("equal") ELSE Out.String("differ") END; Out.Ln;
  IF L9_StrLib.Long > t THEN Out.String("ordered") ELSE Out.String("not ordered") END; Out.Ln;
  Out.Int(L9_StrLib.n, 0); Out.Ln
END L9_ImportStr.
