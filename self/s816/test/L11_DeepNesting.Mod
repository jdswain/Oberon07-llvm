MODULE L11_DeepNesting;
  IMPORT Out;
  VAR a, b, c: INTEGER;
BEGIN
  (* Deeply nested IF *)
  a := 1; b := 2; c := 3;
  IF a = 1 THEN
    IF b = 2 THEN
      IF c = 3 THEN
        IF a + b = 3 THEN
          IF b + c = 5 THEN
            IF a + b + c = 6 THEN
              Out.Int(6, 1); Out.Ln
            END
          END
        END
      END
    END
  END;
  (* Triple-nested WHILE *)
  a := 0;
  WHILE a < 3 DO
    b := 0;
    WHILE b < 3 DO
      c := 0;
      WHILE c < 3 DO
        IF (a = 2) & (b = 1) & (c = 0) THEN
          Out.Int(210, 1); Out.Ln
        END;
        c := c + 1
      END;
      b := b + 1
    END;
    a := a + 1
  END
END L11_DeepNesting.
