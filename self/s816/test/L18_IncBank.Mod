MODULE L18_IncBank; (* INC, DEC, INCL and EXCL on a record a pointer
   points to outside bank 0: through the pointer's bank, not bank 0 *)
  IMPORT SYSTEM, Out;
  TYPE P = POINTER TO R; R = RECORD a, n: INTEGER; b: BYTE; s: SET END;
  VAR p: P; l: LONGINT; k: INTEGER;
  PROCEDURE Bump(VAR k: INTEGER); BEGIN INC(k, 10) END Bump;
BEGIN
  l := 30100H; p := SYSTEM.VAL(P, l);
  p.n := 5; p.b := 7; p.s := {};
  INC(p.n); INC(p.n, 3); DEC(p.n); INC(p.b); INCL(p.s, 3); INCL(p.s, 0); EXCL(p.s, 0);
  Bump(p.n);
  Out.Int(p.n, 4); Out.Int(p.b, 4); Out.Int(ORD(3 IN p.s), 2); Out.Int(ORD(0 IN p.s), 2);
  SYSTEM.GET(3, 0102H, k); Out.Int(k, 4); Out.Ln
END L18_IncBank.
