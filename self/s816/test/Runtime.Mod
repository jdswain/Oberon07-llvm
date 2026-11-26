MODULE Runtime;

  PROCEDURE Mul*(a, b: INTEGER): INTEGER;
    VAR result, neg: INTEGER;
  BEGIN
    result := 0;
    neg := 0;
    IF a < 0 THEN a := -a; neg := neg + 1 END;
    IF b < 0 THEN b := -b; neg := neg + 1 END;
    WHILE b # 0 DO
      IF AND(b, 1) # 0 THEN
        result := result + a
      END;
      a := ASL(a, 1);
      b := LSR(b, 1)
    END;
    IF AND(neg, 1) # 0 THEN result := -result END;
    RETURN result
  END Mul;

  PROCEDURE Div*(a, b: INTEGER): INTEGER;
    VAR q, neg: INTEGER;
  BEGIN
    neg := 0;
    IF a < 0 THEN a := -a; neg := neg + 1 END;
    IF b < 0 THEN b := -b; neg := neg + 1 END;
    q := 0;
    WHILE a >= b DO
      a := a - b;
      q := q + 1
    END;
    IF AND(neg, 1) # 0 THEN q := -q END;
    RETURN q
  END Div;

  PROCEDURE Mod*(a, b: INTEGER): INTEGER;
    VAR neg: INTEGER;
  BEGIN
    neg := 0;
    IF a < 0 THEN a := -a; neg := 1 END;
    IF b < 0 THEN b := -b END;
    WHILE a >= b DO
      a := a - b
    END;
    IF neg # 0 THEN a := -a END;
    RETURN a
  END Mod;

END Runtime.
