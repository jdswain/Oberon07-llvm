MODULE L18_Misc; (* ASSERT, relations between conditions, and procedure
   variables holding procedures that are not exported *)
  IMPORT Out;
  TYPE Fn = PROCEDURE (x: INTEGER): INTEGER;
    LFn = PROCEDURE (x, y: LONGINT): LONGINT;
    Pr = PROCEDURE;
  VAR a, b, n: INTEGER; l: LONGINT; f: Fn; g: LFn; p: Pr; t: BOOLEAN;
    tab: ARRAY 3 OF Fn;

  PROCEDURE B(x: BOOLEAN);
  BEGIN IF x THEN Out.Char("T") ELSE Out.Char("F") END
  END B;

  PROCEDURE Double(x: INTEGER): INTEGER;
  BEGIN RETURN x + x + n
  END Double;

  PROCEDURE Square(x: INTEGER): INTEGER;
  BEGIN RETURN x * x
  END Square;

  PROCEDURE Fact(x: INTEGER): INTEGER;
    VAR r: INTEGER; h: Fn;
  BEGIN
    IF x <= 1 THEN r := 1 ELSE h := Fact; r := x * h(x - 1) END;
    RETURN r
  END Fact;

  PROCEDURE Exp*(x: INTEGER): INTEGER;
  BEGIN RETURN x + 1000
  END Exp;

  PROCEDURE LAdd(x, y: LONGINT): LONGINT;
  BEGIN RETURN x * y + l
  END LAdd;

  PROCEDURE Hello;
  BEGIN Out.String("hello"); Out.Ln
  END Hello;

  PROCEDURE Apply(h: Fn; x: INTEGER): INTEGER;
  BEGIN RETURN h(x)
  END Apply;

  PROCEDURE Same(x, y: INTEGER): BOOLEAN;
  BEGIN RETURN (x < 0) = (y < 0)
  END Same;

BEGIN
  (* relations between conditions *)
  a := -3; b := 5; l := 100000;
  B((a < 0) = (b < 0)); B((a < 0) # (b < 0)); B((a < 0) = (b > 0)); B((a < b) = (l > 70000));
  B((l < 0) # (a < 0)); B(Same(a, b)); B(Same(a, a)); B(Same(b, 7));
  t := (a < 0) # (b < 0); B(t); t := (a = -3) = TRUE; B(t); t := (a = -3) = FALSE; B(t);
  IF (a < 0) = (b < 0) THEN Out.Char("1") ELSE Out.Char("0") END;
  IF ((a < 0) OR (b < 0)) = ((a > 0) & (b > 0)) THEN Out.Char("1") ELSE Out.Char("0") END;
  IF (a < 0) & (b > 0) # (b = 6) THEN Out.Char("1") ELSE Out.Char("0") END;
  Out.Ln;
  (* procedure variables *)
  n := 1; f := Double; Out.Int(f(20), 1); Out.Ln;
  f := Square; Out.Int(f(12), 1); Out.Ln;
  Out.Int(Apply(Double, 4), 1); Out.Ln;
  Out.Int(Apply(Square, 9) + Apply(Exp, 1), 1); Out.Ln;
  Out.Int(Fact(7), 1); Out.Ln;
  tab[0] := Double; tab[1] := Square; tab[2] := Exp;
  FOR a := 0 TO 2 DO Out.Int(tab[a](5), 1); Out.Char(" ") END; Out.Ln;
  g := LAdd; l := g(300, 1000); IF l = 400000 THEN Out.String("long ok") ELSE Out.String("long bad") END; Out.Ln;
  p := Hello; p;
  B(f = Square); f := NIL; B(f = NIL); Out.Ln;
  (* ASSERT *)
  a := 2; b := 3;
  ASSERT(TRUE); ASSERT(a < b); ASSERT((a < b) & (b = 3)); ASSERT((a > b) OR (b = 3));
  ASSERT(~(a = b)); ASSERT(l = 400000); ASSERT(l > 70000); t := TRUE; ASSERT(t);
  Out.String("asserts passed"); Out.Ln
END L18_Misc.
