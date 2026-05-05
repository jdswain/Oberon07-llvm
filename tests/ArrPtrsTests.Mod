MODULE ArrPtrsTests;
  IMPORT ArrPtrs, Modules, TestRunner;

  PROCEDURE TestArrayOfPtr*();
    VAR base, sum: INTEGER;
  BEGIN
    base := Modules.LiveObjects();
    sum := ArrPtrs.TestArrayOfPtr();
    IF (sum = 15) & (Modules.LiveObjects() = base)
    THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestArrayOfPtr;

  PROCEDURE TestReplacing*();
    VAR base, r: INTEGER;
  BEGIN
    base := Modules.LiveObjects();
    r := ArrPtrs.TestReplacing();
    IF (r = 303) & (Modules.LiveObjects() = base)
    THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestReplacing;

END ArrPtrsTests.
