MODULE L3_RecordCopy;
  IMPORT Out;
  TYPE Pair = RECORD x, y: INTEGER END;
  VAR a, b: Pair;
BEGIN
  a.x := 10; a.y := 20;
  b := a;
  Out.Int(b.x, 1); Out.Ln();
  Out.Int(b.y, 1); Out.Ln()
END L3_RecordCopy.
