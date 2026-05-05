MODULE MathTests;
  IMPORT Math, TestRunner;

  PROCEDURE TestAdd*();
  BEGIN
    IF (Math.Add(7, 5) = 12) & (Math.Add(-3, 10) = 7)
    THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestAdd;

END MathTests.
