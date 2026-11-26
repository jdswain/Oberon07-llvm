MODULE L11_ManyParams;
  IMPORT Out;

  PROCEDURE Sum8(a, b, c, d, e, f, g, h: INTEGER): INTEGER;
  BEGIN RETURN a + b + c + d + e + f + g + h
  END Sum8;

  PROCEDURE Print8(a, b, c, d, e, f, g, h: INTEGER);
  BEGIN
    Out.Int(a, 1); Out.Ln;
    Out.Int(b, 1); Out.Ln;
    Out.Int(c, 1); Out.Ln;
    Out.Int(d, 1); Out.Ln;
    Out.Int(e, 1); Out.Ln;
    Out.Int(f, 1); Out.Ln;
    Out.Int(g, 1); Out.Ln;
    Out.Int(h, 1); Out.Ln
  END Print8;

BEGIN
  Out.Int(Sum8(1, 2, 3, 4, 5, 6, 7, 8), 1); Out.Ln;
  Print8(10, 20, 30, 40, 50, 60, 70, 80)
END L11_ManyParams.
