MODULE WeakTests;
  IMPORT Weak, Modules, TestRunner;

  PROCEDURE TestBuild*();
    VAR base: INTEGER;
  BEGIN
    Weak.Drop();
    base := Modules.LiveObjects();
    Weak.Build();
    IF Modules.LiveObjects() = base + 3 THEN TestRunner.Pass ELSE TestRunner.Fail END;
    Weak.Drop()
  END TestBuild;

  PROCEDURE TestSum*();
    VAR base: INTEGER;
  BEGIN
    Weak.Drop();
    base := Modules.LiveObjects();
    Weak.Build();
    IF (Weak.Sum() = 6) & (Modules.LiveObjects() = base + 3)
    THEN TestRunner.Pass ELSE TestRunner.Fail END;
    Weak.Drop()
  END TestSum;

  PROCEDURE TestDrop*();
    VAR base: INTEGER;
  BEGIN
    Weak.Drop();
    base := Modules.LiveObjects();
    Weak.Build();
    Weak.Drop();
    IF Modules.LiveObjects() = base THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestDrop;

END WeakTests.
