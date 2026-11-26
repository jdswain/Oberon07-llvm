MODULE L5_SetLiteral;
  IMPORT Out;
  VAR s: SET; x: INTEGER;
BEGIN
  (* Empty set *)
  s := {};
  Out.Hex(ORD(s)); Out.Ln();

  (* Constant elements *)
  s := {1, 3, 5};
  Out.Hex(ORD(s)); Out.Ln();

  (* Single element constant *)
  s := {0};
  Out.Hex(ORD(s)); Out.Ln();

  (* High bits *)
  s := {15};
  Out.Hex(ORD(s)); Out.Ln();

  (* Variable singleton *)
  x := 4;
  s := {x};
  Out.Hex(ORD(s)); Out.Ln();

  (* Variable singleton 0 *)
  x := 0;
  s := {x};
  Out.Hex(ORD(s)); Out.Ln();

  (* Mixed const and variable *)
  x := 8;
  s := {1, x, 15};
  Out.Hex(ORD(s)); Out.Ln()
END L5_SetLiteral.
