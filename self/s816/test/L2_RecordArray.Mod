MODULE L2_RecordArray;
  IMPORT Out;
  TYPE Data = RECORD
    values: ARRAY 3 OF INTEGER;
    count: INTEGER
  END;
  VAR d: Data;
BEGIN
  d.values[0] := 100;
  d.values[1] := 200;
  d.values[2] := 300;
  d.count := 3;
  Out.Int(d.values[0], 1); Out.Ln();
  Out.Int(d.values[1], 1); Out.Ln();
  Out.Int(d.values[2], 1); Out.Ln()
END L2_RecordArray.
