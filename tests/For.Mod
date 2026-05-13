MODULE For;
(* Edge-case coverage for the FOR statement. Loops.Mod already covers
   the happy-path ascending, descending and stride forms — this module
   targets the boundary conditions: empty ranges, single-iteration
   ranges, nested loops, accumulation, and the loop-variable's
   post-loop value. *)

  PROCEDURE EmptyAsc*(): INTEGER;
  (* lo > hi with default step +1 → body must NOT execute. Pascal /
     Oberon-07 semantics: the entry test runs before the first
     iteration. Expected: 0. *)
    VAR i, count: INTEGER;
  BEGIN
    count := 0;
    FOR i := 10 TO 5 DO INC(count) END;
    RETURN count
  END EmptyAsc;

  PROCEDURE EmptyDesc*(): INTEGER;
  (* Descending range where lo < hi → again the body must not execute.
     Expected: 0. *)
    VAR i, count: INTEGER;
  BEGIN
    count := 0;
    FOR i := 1 TO 10 BY -1 DO INC(count) END;
    RETURN count
  END EmptyDesc;

  PROCEDURE SingleIter*(): INTEGER;
  (* lo = hi → body runs exactly once. Expected: 1. *)
    VAR i, count: INTEGER;
  BEGIN
    count := 0;
    FOR i := 7 TO 7 DO INC(count) END;
    RETURN count
  END SingleIter;

  PROCEDURE DescStride*(): INTEGER;
  (* Descending with step -2: 10, 8, 6, 4, 2 → sum 30. Expected: 30. *)
    VAR i, s: INTEGER;
  BEGIN
    s := 0;
    FOR i := 10 TO 2 BY -2 DO s := s + i END;
    RETURN s
  END DescStride;

  PROCEDURE Nested*(): INTEGER;
  (* 3 × 3 multiplication-table sum:
       i\j   1  2  3
        1    1  2  3
        2    2  4  6
        3    3  6  9
     Total = 36. Expected: 36. *)
    VAR i, j, s: INTEGER;
  BEGIN
    s := 0;
    FOR i := 1 TO 3 DO
      FOR j := 1 TO 3 DO
        s := s + i * j
      END
    END;
    RETURN s
  END Nested;

  PROCEDURE NegToPos*(): INTEGER;
  (* Range crossing zero: -2..2 sums to 0. Expected: 0. *)
    VAR i, s: INTEGER;
  BEGIN
    s := 0;
    FOR i := -2 TO 2 DO s := s + i END;
    RETURN s
  END NegToPos;

  PROCEDURE BoundsOnce*(): INTEGER;
  (* The upper bound should be evaluated once at loop entry; a
     mutation inside the body must NOT extend the range. Use a global-
     style accumulator to capture the count. Expected: 5 (the original
     bound), not 10. *)
    VAR i, hi, count: INTEGER;
  BEGIN
    count := 0; hi := 5;
    FOR i := 1 TO hi DO
      INC(count);
      hi := 10   (* spec: re-evaluation of hi here must not extend *)
    END;
    RETURN count
  END BoundsOnce;

  PROCEDURE PostLoopValue*(): INTEGER;
  (* On exit, the loop variable holds the first value that failed
     the entry test. For `FOR i := 1 TO 4` that's 5 (i = 4 + step).
     This isn't part of Oberon-07's guaranteed semantics but our
     codegen implements it consistently — fixing the behaviour here
     means any future change is intentional. Expected: 5. *)
    VAR i: INTEGER;
  BEGIN
    FOR i := 1 TO 4 DO END;
    RETURN i
  END PostLoopValue;

  PROCEDURE SumWithStep*(): INTEGER;
  (* Stride larger than the range — body should run exactly once.
     FOR i := 1 TO 5 BY 100 → i takes only the value 1. Expected: 1. *)
    VAR i, s: INTEGER;
  BEGIN
    s := 0;
    FOR i := 1 TO 5 BY 100 DO s := s + i END;
    RETURN s
  END SumWithStep;

END For.
