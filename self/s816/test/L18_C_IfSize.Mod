MODULE L18_C_IfSize; IMPORT Out, SYSTEM, B := L18_C_IfBase;
TYPE
  Buf = POINTER TO BufDesc;
  BufDesc = RECORD IMPLEMENTS B.Sink n: INTEGER END;
  Own = INTERFACE PROCEDURE Put(c: CHAR) END;
VAR x, y: Buf; s: B.Sink; q: B.Pair;
PROCEDURE (b: Buf) Put(c: CHAR);
BEGIN INC(b.n); Out.Char(c)
END Put;
BEGIN NEW(x); NEW(y);
  B.Send(x, y, 7); Out.Char(" "); Out.Int(B.last, 0); Out.Ln;
  B.Take(s, y); s.Put("y"); Out.Int(y.n, 0); Out.Ln;
  q.k := 5; B.Take(q.b, x); q.b.Put("b"); Out.Int(q.k, 0);
  B.Set(y, 9); s := B.p.b; s.Put("p"); Out.Int(B.p.k, 0); Out.Int(y.n, 0); Out.Ln;
  Out.Int(B.Size(), 0); Out.Char(" "); Out.Int(SYSTEM.SIZE(B.Pair), 0); Out.Char(" ");
  Out.Int(SYSTEM.SIZE(B.Sink), 0); Out.Char(" "); Out.Int(SYSTEM.SIZE(Own), 0); Out.Ln
END L18_C_IfSize.
