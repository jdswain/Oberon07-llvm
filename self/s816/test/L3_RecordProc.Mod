MODULE L3_RecordProc;
  IMPORT Out;
  TYPE Pair = RECORD x, y: INTEGER END;
  VAR a, b, c: Pair;

  PROCEDURE MakePair(px, py: INTEGER; VAR p: Pair);
  BEGIN
    p.x := px; p.y := py
  END MakePair;

  PROCEDURE AddPairs(a, b: Pair; VAR c: Pair);
  BEGIN
    c.x := a.x + b.x;
    c.y := a.y + b.y
  END AddPairs;

BEGIN
  MakePair(10, 20, a);
  MakePair(20, 50, b);
  AddPairs(a, b, c);
  Out.Int(c.x, 1); Out.Ln();
  Out.Int(c.y, 1); Out.Ln()
END L3_RecordProc.
