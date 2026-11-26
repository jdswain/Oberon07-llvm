MODULE L2_Record;
  IMPORT Out;
  TYPE Pair = RECORD x, y: INTEGER END;
  VAR p: Pair;
BEGIN
  p.x := 42;
  p.y := 7;
  Out.Int(p.x, 1); Out.Ln();
  Out.Int(p.y, 1); Out.Ln()
END L2_Record.
