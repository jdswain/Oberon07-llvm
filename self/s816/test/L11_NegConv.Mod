MODULE L11_NegConv;
  (* DIV of a negative INTEGER by a divisor not a power of two: the loop
     was unsigned, -360 DIV 20 gave 3258 (now ORGFP's I_DIV, signed as
     Oberon's: rounded down); a LONGINT made an INTEGER first, and as a
     procedure's result; a LONGINT compared with a constant past a byte *)
  IMPORT Out;

  VAR l: LONGINT; i, k: INTEGER;

  PROCEDURE P(x: LONGINT): INTEGER;
    VAR n: INTEGER;
  BEGIN n := x RETURN n
  END P;

BEGIN
  l := 360; l := -l; i := l; Out.Int(i, 0); Out.Ln;
  Out.Int(i DIV 20, 0); Out.Ln;
  Out.Int(P(l) DIV 20, 0); Out.Ln;
  k := -360; Out.Int(k DIV 20, 0); Out.Ln;
  l := 8364; IF l < 256 THEN Out.String("small") ELSE Out.String("large") END; Out.Ln;
  l := 0; l := l * 10 + (ORD("8") - ORD("0")); l := l * 10 + 3; Out.Int(l, 0); Out.Ln
END L11_NegConv.
