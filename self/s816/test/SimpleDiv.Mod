MODULE SimpleDiv;
  IMPORT Out;

  VAR a, b, q: INTEGER;

BEGIN
  a := 42; b := 6;
  q := 0;
  WHILE a >= b DO
    a := a - b;
    q := q + 1
  END;
  Out.Hex(q); Out.Ln();
  Out.Hex(a); Out.Ln()
END SimpleDiv.
