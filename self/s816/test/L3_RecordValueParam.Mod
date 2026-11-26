MODULE L3_RecordValueParam;
  IMPORT Out;
  TYPE Pair = RECORD x, y: INTEGER END;
  VAR r: Pair;

  PROCEDURE Show(p: Pair);
  BEGIN
    Out.Int(p.x, 1); Out.Ln();
    Out.Int(p.y, 1); Out.Ln()
  END Show;

BEGIN
  r.x := 5; r.y := 15;
  Show(r)
END L3_RecordValueParam.
