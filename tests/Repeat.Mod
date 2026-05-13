MODULE Repeat;
(* Subject module — exposes a handful of REPEAT-UNTIL loops with
   easily-checked iteration counts. RepeatTests asserts them.

   Bug seen 2026-05-12 while building the oed editor: a REPEAT body
   executes exactly once regardless of the UNTIL condition.

   Root cause is in the LLVM backend: the conditional branch at the
   bottom of the REPEAT is emitted with its true/false labels
   swapped. For `REPEAT body UNTIL n >= 3` the IR currently emits:

       br i1 %cmp, label %here, label %cb_cont   ; loops while TRUE

   when REPEAT semantics demand the inverse — loop back when the
   UNTIL condition is FALSE, exit when TRUE:

       br i1 %cmp, label %cb_cont, label %here

   All variants below (single bool, OR, integer compare, parenthesised
   OR) fail identically, confirming the bug is in the loop construct
   rather than in any specific UNTIL-expression form. The matching
   WHILE formulation (`EquivalentWhile`) does the right thing,
   confirming the codegen for `WHILE cond DO` is correct. *)

  PROCEDURE CountWithOr*(): INTEGER;
  (* Plain local BOOLEAN operands joined with OR. Should iterate
     until a becomes TRUE (after 3 INCs). Expected return: 3. *)
    VAR a, b: BOOLEAN; n: INTEGER;
  BEGIN
    n := 0; a := FALSE; b := FALSE;
    REPEAT
      INC(n);
      a := n >= 3
    UNTIL a OR b;
    RETURN n
  END CountWithOr;

  PROCEDURE CountSingleBool*(): INTEGER;
  (* Single boolean operand, no OR. Expected return: 3. *)
    VAR a: BOOLEAN; n: INTEGER;
  BEGIN
    n := 0; a := FALSE;
    REPEAT
      INC(n);
      a := n >= 3
    UNTIL a;
    RETURN n
  END CountSingleBool;

  PROCEDURE CountIntCompare*(): INTEGER;
  (* Integer comparison in UNTIL — no boolean variable at all.
     Expected return: 3. *)
    VAR n: INTEGER;
  BEGIN
    n := 0;
    REPEAT
      INC(n)
    UNTIL n >= 3;
    RETURN n
  END CountIntCompare;

  PROCEDURE CountParenOr*(): INTEGER;
  (* Same as CountWithOr but the OR is parenthesised, in case the
     compiler is parsing UNTIL <expr> oddly. Expected: 3. *)
    VAR a, b: BOOLEAN; n: INTEGER;
  BEGIN
    n := 0; a := FALSE; b := FALSE;
    REPEAT
      INC(n);
      a := n >= 3
    UNTIL (a OR b);
    RETURN n
  END CountParenOr;

  PROCEDURE EquivalentWhile*(): INTEGER;
  (* Sanity baseline: the same loop expressed as WHILE with an
     emulated do-at-least-once flag. Should also return 3 — if this
     diverges, the bug is elsewhere. *)
    VAR n: INTEGER; done: BOOLEAN;
  BEGIN
    n := 0; done := FALSE;
    WHILE ~done DO
      INC(n);
      IF n >= 3 THEN done := TRUE END
    END;
    RETURN n
  END EquivalentWhile;

END Repeat.
