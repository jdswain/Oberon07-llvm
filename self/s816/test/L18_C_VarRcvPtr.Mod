MODULE L18_C_VarRcvPtr; IMPORT Out;
TYPE R = RECORD a, b: INTEGER END;
  P = POINTER TO R;
  E = RECORD (R) c: INTEGER END;
  PE = POINTER TO E;
  H = RECORD p: P END;
  WR = RECORD x: INTEGER; f: R END; W = POINTER TO WR;
VAR w: W; a: ARRAY 3 OF R; p: P; q: PE; r: R; h: H; i: INTEGER;
PROCEDURE (VAR s: R) Set(x, y: INTEGER);
BEGIN s.a := x; s.b := y
END Set;
PROCEDURE (VAR s: R) Sum(k: INTEGER): INTEGER;
BEGIN RETURN s.a + s.b + k
END Sum;
PROCEDURE Loc(): INTEGER;
  VAR lp: P; t: INTEGER;
BEGIN NEW(lp); lp.Set(5, 6); t := lp^.Sum(1); RETURN t + lp.a
END Loc;
BEGIN
  NEW(p); p.Set(3, 4); Out.Int(p.a, 0); Out.Char(" "); Out.Int(p.b, 0); Out.Ln;
  p^.Set(7, 8); Out.Int(p.a, 0); Out.Char(" "); Out.Int(p.b, 0); Out.Ln;
  Out.Int(p.Sum(100), 0); Out.Ln;
  i := 2 + p.Sum(10); Out.Int(i, 0); Out.Ln;
  NEW(q); q.Set(1, 2); Out.Int(q.Sum(0), 0); Out.Ln;
  h.p := p; h.p.Set(20, 30); Out.Int(h.p.Sum(0), 0); Out.Ln;
  r.Set(9, 9); Out.Int(r.Sum(0), 0); Out.Ln;
  Out.Int(Loc(), 0); Out.Ln;
  NEW(w); w.f.Set(40, 2); Out.Int(w.f.Sum(0), 0); Out.Char(" "); Out.Int(w.f.a, 0); Out.Ln;
  i := 1; a[i].Set(11, 12); i := 2; a[i].Set(13, 14);
  Out.Int(a[1].a, 0); Out.Char(" "); Out.Int(a[2].b, 0); Out.Char(" "); i := 1; Out.Int(a[i].Sum(0), 0); Out.Ln
END L18_C_VarRcvPtr.
