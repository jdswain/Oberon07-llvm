MODULE L18_ArithSums; (* checksums of INTEGER and LONGINT products,
   quotients and remainders (DIV and MOD rounding down), shifts by
   constants and array indexing, of pseudo-random operands, as oc816 makes
   them with -x (the core's MUL, DIV and shifts by n) or without: the
   expected sums are Python's, of the same operands *)
  IMPORT SYSTEM, Out;

  CONST N = 300;

  TYPE
    R3 = RECORD a: INTEGER; b: BYTE END;
    R6 = RECORD a, b, c: INTEGER END;
    R7 = RECORD a, b, c: INTEGER; d: BYTE END;
    R12 = RECORD a: ARRAY 6 OF INTEGER END;
    R20 = RECORD a: ARRAY 10 OF INTEGER END;
    R52 = RECORD a: ARRAY 26 OF INTEGER END;
    R32 = RECORD a: ARRAY 16 OF INTEGER END;

  VAR seed, h: INTEGER;
    a3: ARRAY 40 OF R3; a6: ARRAY 40 OF R6; a7: ARRAY 40 OF R7;
    a12: ARRAY 40 OF R12; a20: ARRAY 40 OF R20; a52: ARRAY 40 OF R52;
    a32: ARRAY 40 OF R32;

  PROCEDURE Rnd(): INTEGER;
  BEGIN seed := EOR(seed, ASL(seed, 7)); seed := EOR(seed, LSR(seed, 9)); seed := EOR(seed, ASL(seed, 8))
  RETURN seed
  END Rnd;

  PROCEDURE Mix(v: INTEGER);
  BEGIN h := EOR(ASL(h, 1), LSR(h, 15)) + v
  END Mix;

  PROCEDURE MixL(v: LONGINT);
    VAR w: LONGINT;
  BEGIN Mix(SYSTEM.VAL(INTEGER, v)); w := v DIV 65536; Mix(SYSTEM.VAL(INTEGER, w))
  END MixL;

  PROCEDURE Sum(name: ARRAY OF CHAR);
  BEGIN Out.String(name); Out.String(" "); Out.Hex(h); Out.Ln; h := 0
  END Sum;

  (* a LONGINT of 1 to 32 significant bits, of either sign *)
  PROCEDURE RndL(): LONGINT;
    VAR l: LONGINT; k: INTEGER;
  BEGIN l := Rnd(); l := l * 65536 + Rnd() MOD 65536; k := Rnd() MOD 32;
    WHILE k > 0 DO l := l DIV 2; DEC(k) END;
    RETURN l
  END RndL;

  (* a positive divisor: 1 .. 255, 256 .. 32767, 32768 .. 65535, or larger *)
  PROCEDURE Divisor(): LONGINT;
    VAR l: LONGINT; k: INTEGER;
  BEGIN k := Rnd() MOD 4;
    IF k = 0 THEN l := Rnd() MOD 255 + 1
    ELSIF k = 1 THEN l := Rnd() MOD 32512 + 256
    ELSIF k = 2 THEN l := Rnd() MOD 16384; l := l * 2 + 32768
    ELSE l := RndL(); IF l < 0 THEN l := -(l + 1) END; IF l < 65536 THEN l := l + 65536 END
    END;
    RETURN l
  END Divisor;

  PROCEDURE IntMul;
    VAR i, x, y: INTEGER;
  BEGIN seed := 1357H;
    FOR i := 1 TO N DO x := Rnd(); y := Rnd();
      Mix(x * y); Mix(x * 3); Mix(x * 10); Mix(x * 100); Mix(x * 1000); Mix(x * (-7)); Mix(x * 12);
      Mix(x * 2); Mix(x * 4); Mix(x * 64); Mix(x * 16384); Mix(5 * x); Mix(8 * x); Mix(x * 1)
    END;
    Sum("imul")
  END IntMul;

  PROCEDURE IntDiv;
    VAR i, x, y: INTEGER;
  BEGIN seed := 2468H;
    FOR i := 1 TO N DO x := Rnd(); y := Rnd() MOD 32767 + 1; IF i MOD 3 = 0 THEN y := y MOD 300 + 1 END;
      Mix(x DIV y); Mix(x MOD y);
      Mix(x DIV 1); Mix(x DIV 2); Mix(x DIV 3); Mix(x DIV 7); Mix(x DIV 10); Mix(x DIV 16); Mix(x DIV 60);
      Mix(x DIV 255); Mix(x DIV 256); Mix(x DIV 1000); Mix(x DIV 16384); Mix(x DIV 32767);
      Mix(x MOD 1); Mix(x MOD 2); Mix(x MOD 3); Mix(x MOD 7); Mix(x MOD 10); Mix(x MOD 16); Mix(x MOD 60);
      Mix(x MOD 255); Mix(x MOD 256); Mix(x MOD 1000); Mix(x MOD 32767)
    END;
    x := -32767 - 1; Mix(x DIV 1); Mix(x DIV 7); Mix(x MOD 7); x := 32767; Mix(x DIV 1); Mix(x MOD 32767);
    Sum("idiv")
  END IntDiv;

  PROCEDURE IntShift;
    VAR i, x, n: INTEGER;
  BEGIN seed := 3579H;
    FOR i := 1 TO N DO x := Rnd(); n := Rnd() MOD 16;
      Mix(ASL(x, 0)); Mix(ASL(x, 1)); Mix(ASL(x, 2)); Mix(ASL(x, 3)); Mix(ASL(x, 5)); Mix(ASL(x, 8)); Mix(ASL(x, 15));
      Mix(LSR(x, 1)); Mix(LSR(x, 2)); Mix(LSR(x, 4)); Mix(LSR(x, 7)); Mix(LSR(x, 12)); Mix(LSR(x, 15));
      Mix(ASL(x, n)); Mix(LSR(x, n))
    END;
    Sum("ishift")
  END IntShift;

  PROCEDURE LongMul;
    VAR i, s: INTEGER; x, y: LONGINT;
  BEGIN seed := 4680H;
    FOR i := 1 TO N DO x := RndL(); y := RndL(); s := Rnd();
      MixL(x * y); MixL(x * s); MixL(s * x); MixL(x * 3); MixL(x * 10); MixL(x * 1000); MixL(x * 100000);
      MixL(x * (-3)); MixL(x * 2); MixL(x * 4); MixL(x * 256); MixL(x * 4096); MixL(x * 65536);
      MixL(x * 131072); MixL(x * 1048576); MixL(x * 1073741824)
    END;
    Sum("lmul")
  END LongMul;

  PROCEDURE LongDiv;
    VAR i: INTEGER; x, y: LONGINT;
  BEGIN seed := 5791H;
    FOR i := 1 TO N DO x := RndL(); y := Divisor();
      MixL(x DIV y); MixL(x MOD y);
      MixL(x DIV 2); MixL(x DIV 8); MixL(x DIV 65536); MixL(x DIV 131072); MixL(x DIV 1073741824);
      MixL(x DIV 3); MixL(x DIV 10); MixL(x DIV 60); MixL(x DIV 1000); MixL(x DIV 86400); MixL(x DIV 100000);
      MixL(x MOD 2); MixL(x MOD 8); MixL(x MOD 65536); MixL(x MOD 10); MixL(x MOD 86400)
    END;
    x := -2147483647 - 1; MixL(x DIV 1); MixL(x DIV 7); MixL(x MOD 7); MixL(x DIV 65535); MixL(x DIV 65537);
    x := 7FFFFFFFH; MixL(x DIV 1); MixL(x DIV 7); MixL(x MOD 7); MixL(x DIV 65535); MixL(x DIV 65537);
    x := -32768; MixL(x DIV 1); MixL(x DIV 7); MixL(x MOD 7);
    Sum("ldiv")
  END LongDiv;

  PROCEDURE Index;
    VAR i, j: INTEGER;
  BEGIN seed := 6802H;
    FOR i := 0 TO 39 DO
      a3[i].a := Rnd(); a3[i].b := Rnd() MOD 256; a6[i].c := Rnd(); a7[i].c := Rnd(); a7[i].d := Rnd() MOD 256;
      a12[i].a[5] := Rnd(); a20[i].a[9] := Rnd(); a52[i].a[25] := Rnd(); a32[i].a[15] := Rnd()
    END;
    FOR j := 1 TO N DO i := Rnd() MOD 40;
      Mix(a3[i].a); Mix(a3[i].b); Mix(a6[i].c); Mix(a7[i].c); Mix(a7[i].d);
      Mix(a12[i].a[5]); Mix(a20[i].a[9]); Mix(a52[i].a[25]); Mix(a32[i].a[15])
    END;
    Sum("index")
  END Index;

BEGIN
  h := 0;
  IntMul; IntDiv; IntShift; LongMul; LongDiv; Index;
END L18_ArithSums.
