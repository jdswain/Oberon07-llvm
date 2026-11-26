MODULE L1_Comparison;
  IMPORT Out;
  VAR a, b: INTEGER;
BEGIN
  a := 5; b := 10;
  (* Equal *)
  Out.Bool(a = b); Out.Bool(a = 5); Out.Ln();
  (* Not equal *)
  Out.Bool(a # b); Out.Bool(a # 5); Out.Ln();
  (* Less than *)
  Out.Bool(a < b); Out.Bool(b < a); Out.Ln();
  (* Less or equal *)
  Out.Bool(a <= b); Out.Bool(a <= 5); Out.Bool(b <= a); Out.Ln();
  (* Greater than *)
  Out.Bool(a > b); Out.Bool(b > a); Out.Ln();
  (* Greater or equal *)
  Out.Bool(a >= b); Out.Bool(a >= 5); Out.Bool(b >= a); Out.Ln()
END L1_Comparison.
