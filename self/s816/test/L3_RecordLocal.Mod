MODULE L3_RecordLocal;
  IMPORT Out;
  TYPE Pair = RECORD x, y: INTEGER END;

  PROCEDURE Work;
    VAR r: Pair;
  BEGIN
    r.x := 42; r.y := 7;
    Out.Int(r.x, 1); Out.Ln();
    Out.Int(r.y, 1); Out.Ln()
  END Work;

BEGIN
  Work
END L3_RecordLocal.
