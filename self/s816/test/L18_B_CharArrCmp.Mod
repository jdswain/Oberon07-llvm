MODULE L18_B_CharArrCmp; (* arrays of CHAR compared up to their lengths
   as well as their 0X: a full array has no 0X *)
  IMPORT Out;
  VAR a, b: ARRAY 2 OF CHAR; c: ARRAY 3 OF CHAR; d: ARRAY 4 OF CHAR;

  PROCEDURE B(t: BOOLEAN);
  BEGIN IF t THEN Out.Char("T") ELSE Out.Char("F") END
  END B;

  PROCEDURE P(x: ARRAY OF CHAR; VAR y: ARRAY OF CHAR);
  BEGIN B(x = y); B(x # y); B(x < y); B(x <= y); B(x > y); B(x >= y); B(x = "zz"); B(x < "zzz"); B("zz" = y); Out.Char(" ")
  END P;

BEGIN
  a[0] := "z"; a[1] := "z"; b[0] := "z"; b[1] := "z";
  c := "zz"; d := "zzz";
  B(a = b); B(a # b); B(a < b); B(a <= b); B(a = c); B(c = a); B(a < c); B(a = d); B(a < d); B(d > a);
  B(a = "zz"); B("zz" = a); B(a < "zzz"); B(a > "z"); B(a # "zz"); Out.Char(" ");
  P(a, b); P(a, c); P(c, a); P(a, d); P(d, a); Out.Ln;
  b[1] := "y"; B(a = b); B(a > b); B(b < a); c := "z"; B(a > c); B(c < a); B(c = a); d[2] := 0X; B(a = d); B(d = a); Out.Ln
END L18_B_CharArrCmp.
