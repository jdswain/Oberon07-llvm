MODULE Loops;

  PROCEDURE SumTo*(n: INTEGER): INTEGER;
    VAR i, total: INTEGER;
  BEGIN
    total := 0;
    FOR i := 1 TO n DO
      total := total + i
    END;
    RETURN total
  END SumTo;

  PROCEDURE Countdown*(n: INTEGER): INTEGER;
    VAR i, k: INTEGER;
  BEGIN
    k := 0;
    FOR i := n TO 1 BY -1 DO
      k := k + i * i
    END;
    RETURN k
  END Countdown;

  PROCEDURE Stride*(): INTEGER;
    VAR i, s: INTEGER;
  BEGIN
    s := 0;
    FOR i := 0 TO 10 BY 2 DO
      s := s + i
    END;
    RETURN s
  END Stride;

END Loops.
