MODULE L1_SignedCompare;
  IMPORT Out;
  VAR a, b: INTEGER;
BEGIN
  a := -5; b := 3;
  Out.Bool(a < b); Out.Bool(b < a); Out.Ln();
  Out.Bool(a > b); Out.Bool(b > a); Out.Ln();
  Out.Bool(a <= b); Out.Bool(a <= -5); Out.Ln();
  Out.Bool(a >= b); Out.Bool(a >= -5); Out.Ln();
  (* Compare two negatives *)
  a := -10; b := -3;
  Out.Bool(a < b); Out.Bool(b < a); Out.Ln();
  Out.Bool(a = b); Out.Bool(a # b); Out.Ln()
END L1_SignedCompare.
