MODULE L18_D_SysOps; (* UML: the unsigned 32-bit product; PACK, UNPK of a REAL;
   SYSTEM.INTEN: SEI, CLI *)
  IMPORT SYSTEM, Out;
  TYPE P = POINTER TO R; R = RECORD x: REAL; e: INTEGER END;
  VAR i, j, e: INTEGER; l: LONGINT; x: REAL; b: BOOLEAN; p: P;
  PROCEDURE H(l: LONGINT);
    VAR h, w: INTEGER;
  BEGIN h := l DIV 10000H; w := l MOD 10000H; Out.Char(" "); Out.Hex(h); Out.Hex(w)
  END H;
  PROCEDURE U(a, b: INTEGER): LONGINT;
  BEGIN RETURN UML(a, b)
  END U;
  PROCEDURE Loc(y: REAL; n: INTEGER);
    VAR z: REAL; k: INTEGER;
  BEGIN z := y; PACK(z, n); Out.Real(z, 12); UNPK(z, k); Out.Real(z, 12); Out.Int(k, 4); Out.Ln
  END Loc;
BEGIN
  i := -1; j := -1; l := UML(i, j); H(l);
  i := 300; j := 7; H(UML(i, j));
  i := 8000H; H(UML(i, 2));
  H(UML(0FFFFH, 0FFFFH)); H(U(1234H, 100H));
  l := 10 + UML(i, j) * 2; H(l); Out.Ln;
  x := 3.0; PACK(x, 4); Out.Real(x, 12);
  j := -3; PACK(x, j); Out.Real(x, 12);
  x := -0.75; PACK(x, 1); Out.Real(x, 12);
  x := 0.0; PACK(x, 5); Out.Real(x, 12); Out.Ln;
  x := 48.0; UNPK(x, e); Out.Real(x, 12); Out.Int(e, 4);
  x := -0.375; UNPK(x, e); Out.Real(x, 12); Out.Int(e, 4);
  x := 0.0; e := 9; UNPK(x, e); Out.Real(x, 12); Out.Int(e, 4);
  x := 1.0; UNPK(x, l); Out.Real(x, 12); i := l; Out.Int(i, 4); Out.Ln;
  NEW(p); p.x := 5.0; PACK(p.x, 2); UNPK(p.x, p.e); Out.Real(p.x, 12); Out.Int(p.e, 4); Out.Ln;
  Loc(1.5, 3);
  SYSTEM.INTEN(FALSE); i := i + 1; SYSTEM.INTEN(TRUE);
  b := FALSE; SYSTEM.INTEN(b); b := TRUE; SYSTEM.INTEN(b);
  SYSTEM.INTEN(i > 0);
  Out.String("inten ok"); Out.Ln
END L18_D_SysOps.
