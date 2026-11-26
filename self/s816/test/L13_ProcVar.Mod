MODULE L13_ProcVar;
  IMPORT Out;
  TYPE IntProc = PROCEDURE(x: INTEGER);
  VAR p: IntProc;

  PROCEDURE Double*(x: INTEGER);
  BEGIN Out.Int(x * 2, 0); Out.Ln
  END Double;

  PROCEDURE Triple*(x: INTEGER);
  BEGIN Out.Int(x * 3, 0); Out.Ln
  END Triple;

  PROCEDURE Apply(proc: IntProc; val: INTEGER);
  BEGIN proc(val)
  END Apply;
BEGIN
  p := Double; p(5);
  p := Triple; p(5);
  Apply(Double, 7);
  Apply(Triple, 7);
  p := NIL;
  IF p = NIL THEN Out.Int(1, 0); Out.Ln END
END L13_ProcVar.
