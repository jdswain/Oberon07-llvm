MODULE ForTests;
(* FOR-loop boundary tests complementing the basic coverage already
   in LoopsTests. *)

  IMPORT For, TestRunner;

  PROCEDURE TestEmptyAsc*();
  BEGIN
    IF For.EmptyAsc() = 0 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestEmptyAsc;

  PROCEDURE TestEmptyDesc*();
  BEGIN
    IF For.EmptyDesc() = 0 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestEmptyDesc;

  PROCEDURE TestSingleIter*();
  BEGIN
    IF For.SingleIter() = 1 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestSingleIter;

  PROCEDURE TestDescStride*();
  BEGIN
    IF For.DescStride() = 30 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestDescStride;

  PROCEDURE TestNested*();
  BEGIN
    IF For.Nested() = 36 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestNested;

  PROCEDURE TestNegToPos*();
  BEGIN
    IF For.NegToPos() = 0 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestNegToPos;

  PROCEDURE TestBoundsOnce*();
  BEGIN
    IF For.BoundsOnce() = 5 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestBoundsOnce;

  PROCEDURE TestSumWithStep*();
  BEGIN
    IF For.SumWithStep() = 1 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestSumWithStep;

END ForTests.
