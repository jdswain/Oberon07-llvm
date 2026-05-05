MODULE BranchTests;
  IMPORT Branch, TestRunner;

  PROCEDURE TestMax*();
  BEGIN
    IF (Branch.Max(3, 5) = 5) & (Branch.Max(8, 2) = 8) THEN TestRunner.Pass
    ELSE TestRunner.Fail END
  END TestMax;

  PROCEDURE TestSignNegative*();
  BEGIN
    IF Branch.Sign(-7) = -1 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestSignNegative;

  PROCEDURE TestSignZero*();
  BEGIN
    IF Branch.Sign(0) = 0 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestSignZero;

  PROCEDURE TestSignPositive*();
  BEGIN
    IF Branch.Sign(4) = 1 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestSignPositive;

END BranchTests.
