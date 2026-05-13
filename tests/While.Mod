MODULE While;
(* Subject module mirroring Repeat.Mod, but with WHILE...DO loops in
   place of REPEAT...UNTIL. The conditions are deliberately inverted
   (loop while NOT done) so the counts come out the same as their
   REPEAT siblings — easy A/B comparison between the two codegens. *)

  PROCEDURE CountSingleBool*(): INTEGER;
  (* Single boolean operand. Mirror of Repeat.CountSingleBool — loops
     until a becomes TRUE. Expected: 3. *)
    VAR a: BOOLEAN; n: INTEGER;
  BEGIN
    n := 0; a := FALSE;
    WHILE ~a DO
      INC(n);
      a := n >= 3
    END;
    RETURN n
  END CountSingleBool;

  PROCEDURE CountWithAnd*(): INTEGER;
  (* AND in the loop condition. WHILE ~a & ~b — exits when either
     becomes TRUE. Expected: 3. *)
    VAR a, b: BOOLEAN; n: INTEGER;
  BEGIN
    n := 0; a := FALSE; b := FALSE;
    WHILE ~a & ~b DO
      INC(n);
      a := n >= 3
    END;
    RETURN n
  END CountWithAnd;

  PROCEDURE CountIntCompare*(): INTEGER;
  (* Integer comparison in the condition, no boolean variable.
     Expected: 3. *)
    VAR n: INTEGER;
  BEGIN
    n := 0;
    WHILE n < 3 DO
      INC(n)
    END;
    RETURN n
  END CountIntCompare;

  PROCEDURE CountParenAnd*(): INTEGER;
  (* Same as CountWithAnd with explicit parentheses around the AND. *)
    VAR a, b: BOOLEAN; n: INTEGER;
  BEGIN
    n := 0; a := FALSE; b := FALSE;
    WHILE (~a & ~b) DO
      INC(n);
      a := n >= 3
    END;
    RETURN n
  END CountParenAnd;

  PROCEDURE CountNeverEnter*(): INTEGER;
  (* The condition is FALSE on entry; body must NOT execute (this is
     the defining difference between WHILE and REPEAT). Expected: 0. *)
    VAR n: INTEGER;
  BEGIN
    n := 0;
    WHILE FALSE DO INC(n) END;
    RETURN n
  END CountNeverEnter;

  PROCEDURE CountElsifBranches*(): INTEGER;
  (* Oberon-07 WHILE allows ELSIF clauses. Each cycle re-evaluates
     from the top, taking the first matching arm. With n increasing,
     we exit only when n reaches 10. Returns the final n. Expected: 10.
     Encodes: 0..2 take the small-step arm (+1), 3..6 take the medium
     arm (+2), 7..9 take the big arm (+3); 10 falls past all. *)
    VAR n: INTEGER;
  BEGIN
    n := 0;
    WHILE n < 3 DO
      INC(n)
    ELSIF n < 7 DO
      INC(n, 2)
    ELSIF n < 10 DO
      INC(n, 3)
    END;
    RETURN n
  END CountElsifBranches;

END While.
