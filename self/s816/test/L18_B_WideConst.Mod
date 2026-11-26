MODULE L18_B_WideConst; (* an integer constant beyond a word, stored in
   an INTEGER or a BYTE or passed to one: its low bits *)
  IMPORT Out;
  TYPE R = RECORD i: INTEGER; b: BYTE END;
  VAR i: INTEGER; b: BYTE; r: R; p: POINTER TO R; a: ARRAY 3 OF INTEGER;

  PROCEDURE P(x: INTEGER; y: BYTE);
  BEGIN Out.Int(x, 7); Out.Int(y, 5)
  END P;

  PROCEDURE V(VAR x: INTEGER);
  BEGIN x := 100000
  END V;

  PROCEDURE L;
    VAR j: INTEGER; c: BYTE;
  BEGIN j := 123; j := 70000; c := 7; c := 70001; Out.Int(j, 7); Out.Int(c, 5);
    j := -70000; Out.Int(j, 7); Out.Ln
  END L;

BEGIN
  i := 5; i := 70000; Out.Int(i, 7);
  i := 9; i := 100000; Out.Int(i, 7);
  i := -100000; Out.Int(i, 7);
  b := 3; b := 70001; Out.Int(b, 5); Out.Ln;
  P(70000, 1000001); P(-70000, 70002); Out.Ln;
  r.i := 70000; r.b := 70003; Out.Int(r.i, 7); Out.Int(r.b, 5);
  NEW(p); p.i := 100000; p.b := 70004; Out.Int(p.i, 7); Out.Int(p.b, 5);
  a[1] := 70000; Out.Int(a[1], 7); V(i); Out.Int(i, 7); Out.Ln;
  L
END L18_B_WideConst.
