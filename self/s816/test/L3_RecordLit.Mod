MODULE L3_RecordLit;
  IMPORT Out;
  TYPE
    Point = RECORD x, y: INTEGER END;
    Line = RECORD a, b: Point END;
  VAR p: Point; l: Line;
BEGIN
  p := Point{y := 20; x := 10};                              (* named, out of order *)
  Out.Int(p.x, 4); Out.Int(p.y, 4); Out.Ln;
  p := Point{x := 7};                                         (* partial -> y zero-filled *)
  Out.Int(p.x, 4); Out.Int(p.y, 4); Out.Ln;
  l := Line{a := Point{x := 1; y := 2}; b := Point{x := 3; y := 4}};   (* nested *)
  Out.Int(l.a.x, 4); Out.Int(l.a.y, 4); Out.Int(l.b.x, 4); Out.Int(l.b.y, 4); Out.Ln
END L3_RecordLit.
