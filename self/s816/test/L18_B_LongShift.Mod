MODULE L18_B_LongShift; (* ASL, LSR and ROL of a LONGINT on its 32 bits,
   ROL a rotation (of 16 bits of an INTEGER), by constant and variable
   counts; FLT of a LONGINT and of a wide constant *)
  IMPORT SYSTEM, Out;
  VAR l, m: LONGINT; i, n, k: INTEGER; s: SET; r: REAL;

  PROCEDURE H(x: LONGINT);
    VAR h, w: INTEGER;
  BEGIN h := x DIV 10000H; w := x; Out.Char(" "); Out.Hex(h); Out.Hex(w)
  END H;

  PROCEDURE C(x: LONGINT; n: INTEGER);
  BEGIN H(ASL(x, n)); H(LSR(x, n)); H(ROL(x, n))
  END C;

  PROCEDURE F(x: LONGINT);
    VAR r: REAL;
  BEGIN r := FLT(x); H(SYSTEM.VAL(LONGINT, r))
  END F;

BEGIN
  l := 12345678H;
  H(ASL(l, 4)); H(LSR(l, 4)); H(ROL(l, 4)); Out.Ln;
  H(ASL(l, 1)); H(LSR(l, 1)); H(ROL(l, 1)); Out.Ln;
  H(ASL(l, 20)); H(LSR(l, 20)); H(ROL(l, 20)); Out.Ln;
  H(ASL(l, 16)); H(LSR(l, 16)); H(ROL(l, 16)); Out.Ln;
  H(ASL(l, 0)); H(ASL(l, 32)); H(LSR(l, 40)); H(ROL(l, 36)); Out.Ln;
  l := -2; H(LSR(l, 1)); H(ROL(l, 1)); H(ASL(l, 31)); Out.Ln;
  H(ASL(12345678H, 4)); H(LSR(12345678H, 4)); H(ROL(87654321H, 8)); Out.Ln;
  FOR n := 0 TO 33 BY 11 DO C(12345678H, n); C(0F0000001H, n); Out.Ln END;
  l := 80000001H; n := 1; m := 2; H(ROL(l, n)); H(ASL(l, m)); H(LSR(l, m)); Out.Ln;
  i := 8001H; n := 1; Out.Hex(ROL(i, 1)); Out.Char(" "); Out.Hex(ROL(i, n)); Out.Char(" ");
  Out.Hex(ROL(i, 4)); Out.Char(" "); Out.Hex(ROL(-1, 3)); Out.Char(" ");
  n := 12; Out.Hex(ROL(1234H, n)); Out.Char(" "); Out.Hex(ROL(1234H, 12)); Out.Char(" ");
  k := 1234H; Out.Hex(ROL(k, 16)); Out.Char(" "); Out.Hex(ASL(k, 16)); Out.Char(" ");
  n := 16; Out.Hex(ROL(k, n)); Out.Char(" "); Out.Hex(ASL(k, n)); Out.Char(" ");
  s := ROL({0, 15}, 1); Out.Int(ORD(s), 3); Out.Ln;
  F(100000); F(-100000); F(12345678H); F(7FFFFFFFH); F(-80000000H); F(16777217); F(0); F(-7); Out.Ln;
  F(16777219); F(-16777219); F(7FFFFFC0H); F(33554435); F(65536); F(-32768); Out.Ln;
  l := 100000; r := FLT(l); Out.Real(r, 12); l := -1; Out.Real(FLT(l), 12);
  Out.Real(FLT(100000), 12); i := -7; Out.Real(FLT(i), 12); Out.Ln
END L18_B_LongShift.
