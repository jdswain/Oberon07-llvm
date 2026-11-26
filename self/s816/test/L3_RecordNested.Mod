MODULE L3_RecordNested;
  IMPORT Out;
  TYPE
    Inner = RECORD a, b: INTEGER END;
    Outer = RECORD i: Inner; c: INTEGER END;
  VAR x, y: Outer;
BEGIN
  x.i.a := 1; x.i.b := 2; x.c := 3;
  y := x;
  Out.Int(y.i.a, 1); Out.Ln();
  Out.Int(y.i.b, 1); Out.Ln();
  Out.Int(y.c, 1); Out.Ln()
END L3_RecordNested.
