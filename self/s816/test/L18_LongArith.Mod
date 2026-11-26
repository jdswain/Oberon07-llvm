MODULE L18_LongArith; (* LONGINT *, DIV, MOD, INC, DEC, ABS, ODD and mixed INTEGER operands,
   checked against values computed on the host.

   Calls are kept shallow, with the tests in the module body and Hex
   working on globals: em16's default stack has only some 50 bytes above
   the floppy controller's registers. *)
  IMPORT SYSTEM, Out;
  TYPE Rec = RECORD pad: INTEGER; v: LONGINT END;
  VAR a, b, c: LONGINT; i, j, m, n: INTEGER; arr: ARRAY 6 OF LONGINT; r: Rec; li: LONGINT;
    by: BYTE; hk: INTEGER; hd: LONGINT; hs: ARRAY 9 OF CHAR; lr: ARRAY 5 OF LONGINT;
    V: ARRAY 17 OF LONGINT; D: ARRAY 10 OF LONGINT; IV: ARRAY 6 OF INTEGER;

  PROCEDURE Hex(x: LONGINT);
  BEGIN hk := 8;
    WHILE hk > 0 DO hk := hk - 1; hd := x MOD 16; x := x DIV 16;
      IF hd < 10 THEN hs[hk] := CHR(SYSTEM.VAL(INTEGER, hd) + 30H) ELSE hs[hk] := CHR(SYSTEM.VAL(INTEGER, hd) + 37H) END
    END;
    hs[8] := 0X; Out.String(hs); Out.Ln
  END Hex;

  PROCEDURE Id(x: LONGINT): LONGINT;
  BEGIN RETURN x
  END Id;

  PROCEDURE IId(x: INTEGER): INTEGER;
  BEGIN RETURN x
  END IId;

  PROCEDURE Loc(p, q: LONGINT; VAR res: LONGINT);
    VAR t, u: LONGINT; la: ARRAY 3 OF LONGINT; n: INTEGER;
  BEGIN t := p * q; u := p DIV q; la[1] := p MOD q; n := 1;
    INC(t); DEC(u, 2); INC(la[n], q); INC(res, t); DEC(res, la[n]);
    lr[0] := t; lr[1] := u; lr[2] := la[1]; lr[3] := ABS(p - 100);
    IF ODD(p) THEN lr[4] := 1 ELSE lr[4] := 0 END
  END Loc;

BEGIN
  V[0] := 0;
  V[1] := 1;
  V[2] := 7;
  V[3] := -1;
  V[4] := -7;
  V[5] := 10;
  V[6] := 1000;
  V[7] := 65535;
  V[8] := 65536;
  V[9] := 70000;
  V[10] := -70000;
  V[11] := 123456789;
  V[12] := -123456789;
  V[13] := 2147483647;
  V[14] := -2147483647;
  V[15] := 46341;
  V[16] := 3;
  D[0] := 1;
  D[1] := 3;
  D[2] := 7;
  D[3] := 10;
  D[4] := 255;
  D[5] := 256;
  D[6] := 1000;
  D[7] := 65536;
  D[8] := 70000;
  D[9] := 123456789;
  IV[0] := 0;
  IV[1] := 5;
  IV[2] := -5;
  IV[3] := 300;
  IV[4] := -300;
  IV[5] := 32766;

  FOR m := 0 TO 16 DO a := V[m];
    FOR n := 0 TO 16 DO b := V[n]; Hex(a * b) END;
    Hex(a * 10); Hex(3 * a); Hex(a * Id(1000));
    Hex(a DIV 10); Hex(a MOD 10); Hex(a DIV 1000 MOD 7);
    Hex(ABS(a)); IF ODD(a) THEN Hex(1) ELSE Hex(0) END;
    c := a; INC(c); Hex(c); DEC(c); DEC(c); Hex(c); INC(c, 70000); Hex(c); DEC(c, D[9]); Hex(c);
    FOR n := 0 TO 9 DO b := D[n]; Hex(a DIV b); Hex(a MOD b) END;
    FOR n := 0 TO 5 DO i := IV[n];
    Hex(i + a); Hex(a - i); Hex(i - a); Hex(i * a); Hex((i + 1) * a); Hex((i + 1) + Id(a)); Hex(IId(i) - Id(a));
    c := a; INC(c, i); Hex(c); DEC(c, i + i); Hex(c);
    IF i < a THEN Hex(1) ELSE Hex(0) END; IF (i + 1) >= a THEN Hex(1) ELSE Hex(0) END; IF (i + 1) = Id(a) THEN Hex(1) ELSE Hex(0) END;
    IF i > 0 THEN
      Hex(a DIV i); Hex(a MOD i); Hex(a DIV (i + 1)); Hex(i DIV Id(7)); Hex(i MOD Id(7))
    END
    END
  END;
  FOR i := 0 TO 5 DO arr[i] := 100000 * i END;
  i := 3; INC(arr[i]); INC(arr[i], 70000); DEC(arr[i + 1], arr[2]); Hex(arr[3]); Hex(arr[4]);
  li := 2; arr[li] := arr[li] * arr[li + 1]; Hex(arr[2]); Hex(arr[li + 3]);
  r.v := 5; INC(r.v); INC(r.v, arr[1]); DEC(r.v, 3); Hex(r.v); r.v := r.v * r.v; Hex(r.v); Hex(r.v DIV arr[1]); Hex(r.v MOD arr[1]);
  i := 4; arr[i] := arr[i] DIV arr[i - 3] + i; Hex(arr[4]);
  by := 200; a := 1000; Hex(a * by); Hex(by * a); Hex(a DIV by); Hex(by + a);
  j := 7; a := 100000; i := 3; arr[1] := (i * j) + a; Hex(arr[1]); arr[1] := a - (i * j); Hex(arr[1]); arr[1] := (i * j) * a; Hex(arr[1]);
  c := 10; Loc(100003, 17, c); FOR i := 0 TO 4 DO Hex(lr[i]) END; Hex(c);
  Loc(-100003, 17, c); FOR i := 0 TO 4 DO Hex(lr[i]) END; Hex(c);
  Out.String("done"); Out.Ln
END L18_LongArith.
