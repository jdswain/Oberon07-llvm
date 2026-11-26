MODULE L5_SetVariable;
  IMPORT Out;
  VAR s: SET; g: SET;

  PROCEDURE SetParam(s: SET);
  BEGIN
    Out.Hex(ORD(s)); Out.Ln()
  END SetParam;

  PROCEDURE ModifySet(VAR s: SET);
  BEGIN
    INCL(s, 12)
  END ModifySet;

BEGIN
  (* SET in global variable *)
  g := {1, 2, 3};
  Out.Hex(ORD(g)); Out.Ln();

  (* SET as value parameter *)
  SetParam({4, 5, 6});

  (* SET as VAR parameter *)
  g := {0};
  ModifySet(g);
  Out.Hex(ORD(g)); Out.Ln();

  (* SET in local variable *)
  s := {8, 9, 10};
  Out.Hex(ORD(s)); Out.Ln()
END L5_SetVariable.
