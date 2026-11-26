MODULE L2_RecordParam;
  IMPORT Out;
  TYPE Point = RECORD x, y: INTEGER END;
  VAR p: Point;

  PROCEDURE Init(VAR pt: Point);
  BEGIN
    pt.x := 0; pt.y := 0
  END Init;

  PROCEDURE Set(VAR pt: Point; a, b: INTEGER);
  BEGIN
    pt.x := a; pt.y := b
  END Set;

BEGIN
  Init(p);
  Out.Int(p.x, 1); Out.Ln();
  Out.Int(p.y, 1); Out.Ln();
  Set(p, 10, 20);
  Out.Int(p.x, 1); Out.Ln();
  Out.Int(p.y, 1); Out.Ln()
END L2_RecordParam.
