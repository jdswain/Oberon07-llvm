MODULE RepeatTests;
(* REPEAT-UNTIL behavioural tests for the Repeat subject module.
   The bug seen on 2026-05-12 was that the REPEAT body ran exactly
   once regardless of the UNTIL expression — the conditional branch
   at the bottom of the loop had its true/false labels swapped in
   ORG_CBJump. Fix flipped them so we branch back on FALSE, fall
   through on TRUE. *)

  IMPORT Repeat, TestRunner;

  PROCEDURE TestCountWithOr*();
  BEGIN
    IF Repeat.CountWithOr() = 3 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestCountWithOr;

  PROCEDURE TestCountSingleBool*();
  BEGIN
    IF Repeat.CountSingleBool() = 3 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestCountSingleBool;

  PROCEDURE TestCountIntCompare*();
  BEGIN
    IF Repeat.CountIntCompare() = 3 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestCountIntCompare;

  PROCEDURE TestCountParenOr*();
  BEGIN
    IF Repeat.CountParenOr() = 3 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestCountParenOr;

  PROCEDURE TestEquivalentWhile*();
  (* Sanity baseline: the WHILE form should always pass. *)
  BEGIN
    IF Repeat.EquivalentWhile() = 3 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestEquivalentWhile;

END RepeatTests.
