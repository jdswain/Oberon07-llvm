MODULE L18_C_XInit; IMPORT Out, B := L18_C_XBase;
TYPE
  Sq = POINTER TO SqDesc;
  SqDesc = RECORD (B.RectDesc) name: ARRAY 8 OF CHAR END;
  Circ = POINTER TO CircDesc;
  CircDesc = RECORD (B.ShapeDesc) END;
VAR r: B.Rect; s: Sq; c: Circ; t: B.Shape;
PROCEDURE (c: Circ) Name* OVERRIDE;
BEGIN Out.String("circle")
END Name;
PROCEDURE Local(): INTEGER;
  VAR q: B.Rect;
BEGIN q := B.Rect.Make(7, 2); RETURN q.Area() + 1
END Local;
BEGIN
  r := B.Rect.Make(3, 4); Out.Int(r.w, 0); Out.Char(" "); Out.Int(r.h, 0); Out.Char(" "); Out.Int(r.Area(), 0); Out.Ln;
  s := Sq.Make(5, 6); s.name := "sq"; Out.Int(s.Area(), 0); Out.Char(" "); Out.String(s.name); Out.Ln;
  Out.Int(Local() + B.Rect.Make(1, 1).w, 0); Out.Char(" "); Out.Int(B.made, 0); Out.Ln;
  NEW(c); c.n := 4; B.Show(c); t := c; t.Name; Out.Ln;
  NEW(t); t.n := 2; B.Show(t)
END L18_C_XInit.
