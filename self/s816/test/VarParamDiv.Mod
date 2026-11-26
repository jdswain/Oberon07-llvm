MODULE VarParamDiv;
  IMPORT Out;
  VAR q, r: INTEGER;

  PROCEDURE TestDiv(a, b: INTEGER; VAR qq, rr: INTEGER);
  BEGIN
    qq := 0;
    WHILE a >= b DO
      a := a - b;
      qq := qq + 1
    END;
    rr := a
  END TestDiv;

BEGIN
  TestDiv(42, 6, q, r);
  Out.Hex(q); Out.Ln();
  Out.Hex(r); Out.Ln()
END VarParamDiv.
