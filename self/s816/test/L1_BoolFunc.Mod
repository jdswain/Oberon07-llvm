MODULE L1_BoolFunc;
  IMPORT Out;

  VAR g: INTEGER;

  PROCEDURE RetTrue(): BOOLEAN;
  BEGIN RETURN TRUE
  END RetTrue;

  PROCEDURE RetFalse(): BOOLEAN;
  BEGIN RETURN FALSE
  END RetFalse;

  PROCEDURE IsPositive(x: INTEGER): BOOLEAN;
  BEGIN RETURN x > 0
  END IsPositive;

  PROCEDURE IsZero(x: INTEGER): BOOLEAN;
  BEGIN RETURN x = 0
  END IsZero;

  PROCEDURE Run;
    VAR i: INTEGER;
  BEGIN
    (* Test 1: TRUE function in IF *)
    IF RetTrue() THEN Out.Int(1, 1) ELSE Out.Int(0, 1) END;
    Out.Ln;

    (* Test 2: FALSE function in IF *)
    IF RetFalse() THEN Out.Int(1, 1) ELSE Out.Int(0, 1) END;
    Out.Ln;

    (* Test 3: Function with param, TRUE result *)
    IF IsPositive(5) THEN Out.Int(1, 1) ELSE Out.Int(0, 1) END;
    Out.Ln;

    (* Test 4: Function with param, FALSE result *)
    IF IsPositive(-3) THEN Out.Int(1, 1) ELSE Out.Int(0, 1) END;
    Out.Ln;

    (* Test 5: TRUE & TRUE *)
    IF RetTrue() & IsPositive(1) THEN Out.Int(1, 1) ELSE Out.Int(0, 1) END;
    Out.Ln;

    (* Test 6: TRUE & FALSE *)
    IF RetTrue() & RetFalse() THEN Out.Int(1, 1) ELSE Out.Int(0, 1) END;
    Out.Ln;

    (* Test 7: FALSE OR TRUE *)
    IF RetFalse() OR RetTrue() THEN Out.Int(1, 1) ELSE Out.Int(0, 1) END;
    Out.Ln;

    (* Test 8: FALSE OR FALSE *)
    IF RetFalse() OR IsPositive(-1) THEN Out.Int(1, 1) ELSE Out.Int(0, 1) END;
    Out.Ln;

    (* Test 9: Negated function *)
    IF ~RetFalse() THEN Out.Int(1, 1) ELSE Out.Int(0, 1) END;
    Out.Ln;

    (* Test 10: Function in WHILE *)
    g := 3;
    i := 0;
    WHILE IsPositive(g) DO
      INC(i);
      DEC(g)
    END;
    Out.Int(i, 1);
    Out.Ln;

    (* Test 11: Function result assigned then tested *)
    IF IsZero(0) THEN Out.Int(1, 1) ELSE Out.Int(0, 1) END;
    Out.Ln;

    (* Test 12: NOT of TRUE function *)
    IF ~RetTrue() THEN Out.Int(1, 1) ELSE Out.Int(0, 1) END;
    Out.Ln
  END Run;

BEGIN
  Run
END L1_BoolFunc.
