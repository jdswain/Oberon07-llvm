MODULE L18_C_IfVar; IMPORT Out, SYSTEM;
TYPE
  Sink = INTERFACE PROCEDURE Put(c: CHAR); PROCEDURE Count(): INTEGER END;
  Buf = POINTER TO BufDesc;
  BufDesc = RECORD IMPLEMENTS Sink n, id: INTEGER END;
  Box = RECORD k: INTEGER; s: Sink END;
VAR a, b: Buf; s, t: Sink; bx: Box; n: INTEGER;
PROCEDURE (b: Buf) Put(c: CHAR);
BEGIN INC(b.n); Out.Char(c)
END Put;
PROCEDURE (b: Buf) Count(): INTEGER;
BEGIN RETURN b.n * 100 + b.id
END Count;
PROCEDURE Pick(VAR v: Sink; x: Buf);
BEGIN v := x
END Pick;
PROCEDURE Swap(VAR x, y: Sink);
  VAR z: Sink;
BEGIN z := x; x := y; y := z
END Swap;
PROCEDURE Use(VAR v: Sink): INTEGER;
BEGIN v.Put("u"); Out.Bool(v IS Buf); Out.Int(v(Buf).id, 0); RETURN v.Count()
END Use;
PROCEDURE Nil(VAR v: Sink);
BEGIN v := NIL
END Nil;
PROCEDURE InBox(VAR r: Box);
BEGIN r.s.Put("r"); r.k := r.s.Count(); r.s := a
END InBox;
PROCEDURE Local(): INTEGER;
  VAR l: Sink;
BEGIN Pick(l, b); RETURN Use(l)
END Local;
BEGIN
  NEW(a); a.id := 1; NEW(b); b.id := 2;
  Pick(s, a); Out.Int(s.Count(), 0); Out.Ln;
  t := b; Swap(s, t); Out.Int(s.Count(), 0); Out.Char(" "); Out.Int(t.Count(), 0); Out.Ln;
  n := Use(s); Out.Char(" "); Out.Int(n, 0); Out.Ln;
  Out.Int(Local(), 0); Out.Ln;
  Nil(s); Out.Bool(s = NIL); Out.Bool(t # NIL); Out.Ln;
  bx.s := b; InBox(bx); Out.Char(" "); Out.Int(bx.k, 0); Out.Bool(bx.s = a); Out.Ln;
  Out.Int(SYSTEM.SIZE(Sink), 0); Out.Ln
END L18_C_IfVar.
