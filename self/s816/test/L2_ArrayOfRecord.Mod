MODULE L2_ArrayOfRecord;
  IMPORT Out;
  TYPE Point = RECORD x, y: INTEGER END;
  VAR pts: ARRAY 3 OF Point;
      i: INTEGER;
BEGIN
  pts[0].x := 1; pts[0].y := 10;
  pts[1].x := 2; pts[1].y := 20;
  pts[2].x := 3; pts[2].y := 30;
  i := 0;
  WHILE i < 3 DO
    Out.Int(pts[i].x, 1); Out.Ln();
    Out.Int(pts[i].y, 1); Out.Ln();
    i := i + 1
  END
END L2_ArrayOfRecord.
