MODULE StackRecTests;
  IMPORT StackRec, Modules, TestRunner;

  PROCEDURE TestUseLocalPair*();
    VAR base, sum: INTEGER;
  BEGIN
    base := Modules.LiveObjects();
    sum := StackRec.UseLocalPair();
    IF (sum = 30) & (Modules.LiveObjects() = base)
    THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestUseLocalPair;

  PROCEDURE TestLeakIfBroken*();
    VAR base: INTEGER;
  BEGIN
    base := Modules.LiveObjects();
    StackRec.LeakIfBroken(100);
    IF Modules.LiveObjects() = base THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestLeakIfBroken;

END StackRecTests.
