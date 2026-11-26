MODULE L5_SetInclExcl;
  IMPORT Out;
  VAR s: SET; x: INTEGER;
BEGIN
  (* INCL with const *)
  s := {};
  INCL(s, 3);
  Out.Hex(ORD(s)); Out.Ln();

  (* INCL with variable *)
  s := {};
  x := 7;
  INCL(s, x);
  Out.Hex(ORD(s)); Out.Ln();

  (* Multiple INCLs *)
  s := {};
  INCL(s, 0);
  INCL(s, 4);
  INCL(s, 8);
  Out.Hex(ORD(s)); Out.Ln();

  (* EXCL with const *)
  s := {0..7};
  EXCL(s, 3);
  Out.Hex(ORD(s)); Out.Ln();

  (* EXCL with variable *)
  s := {0..15};
  x := 0;
  EXCL(s, x);
  Out.Hex(ORD(s)); Out.Ln();

  (* INCL then EXCL *)
  s := {};
  INCL(s, 5);
  INCL(s, 10);
  EXCL(s, 5);
  Out.Hex(ORD(s)); Out.Ln()
END L5_SetInclExcl.
