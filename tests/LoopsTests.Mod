MODULE LoopsTests;
  IMPORT Loops, TestRunner;

  PROCEDURE TestSumTo*();
  BEGIN
    IF (Loops.SumTo(10) = 55) & (Loops.SumTo(100) = 5050) THEN TestRunner.Pass
    ELSE TestRunner.Fail END
  END TestSumTo;

  PROCEDURE TestCountdown*();
  BEGIN
    (* 1 + 4 + 9 + 16 + 25 = 55 *)
    IF Loops.Countdown(5) = 55 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestCountdown;

  PROCEDURE TestStride*();
  BEGIN
    (* 0 + 2 + 4 + 6 + 8 + 10 = 30 *)
    IF Loops.Stride() = 30 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestStride;

END LoopsTests.
