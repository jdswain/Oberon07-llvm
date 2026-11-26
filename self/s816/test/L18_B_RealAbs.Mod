MODULE L18_B_RealAbs; (* ABS of a REAL constant, folded: its sign bit
   cleared *)
  IMPORT Out;
  CONST k = ABS(-2.5); m = ABS(2.5); n = ABS(-1.0E-6); MinusPi = -3.1415927; p = ABS(MinusPi);
  VAR x: REAL;
BEGIN
  Out.Real(k, 12); Out.Real(m, 12); Out.Real(n, 12); Out.Real(p, 12); Out.Ln;
  x := -2.5; Out.Real(ABS(x), 12); Out.Real(ABS(-0.0), 12); Out.Int(ABS(-7), 4); Out.Ln
END L18_B_RealAbs.
