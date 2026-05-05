MODULE ArcConsTests;
  IMPORT ArcCons, Modules, TestRunner;

  PROCEDURE TestBeNonNil*();
    VAR base: INTEGER; b: BOOLEAN;
  BEGIN
    base := Modules.LiveObjects();
    b := ArcCons.TestBeNonNil();
    IF b & (Modules.LiveObjects() = base)
    THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestBeNonNil;

  PROCEDURE TestCallChain*();
    VAR base, v: INTEGER;
  BEGIN
    base := Modules.LiveObjects();
    v := ArcCons.TestCallChain();
    IF (v = 99) & (Modules.LiveObjects() = base)
    THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestCallChain;

  PROCEDURE TestRecAssign*();
    VAR base, v: INTEGER;
  BEGIN
    base := Modules.LiveObjects();
    v := ArcCons.TestRecAssign();
    IF (v = 33) & (Modules.LiveObjects() = base)
    THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestRecAssign;

END ArcConsTests.
