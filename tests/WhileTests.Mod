MODULE WhileTests;
(* Assertion tests for While.Mod. Mirror of RepeatTests so that
   regressing one codegen is immediately visible alongside the other. *)

  IMPORT While, TestRunner;

  PROCEDURE TestCountSingleBool*();
  BEGIN
    IF While.CountSingleBool() = 3 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestCountSingleBool;

  PROCEDURE TestCountWithAnd*();
  BEGIN
    IF While.CountWithAnd() = 3 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestCountWithAnd;

  PROCEDURE TestCountIntCompare*();
  BEGIN
    IF While.CountIntCompare() = 3 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestCountIntCompare;

  PROCEDURE TestCountParenAnd*();
  BEGIN
    IF While.CountParenAnd() = 3 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestCountParenAnd;

  PROCEDURE TestCountNeverEnter*();
  (* WHILE FALSE — body never runs. Distinguishes WHILE from REPEAT. *)
  BEGIN
    IF While.CountNeverEnter() = 0 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestCountNeverEnter;

  PROCEDURE TestCountElsifBranches*();
  BEGIN
    IF While.CountElsifBranches() = 10 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestCountElsifBranches;

END WhileTests.
