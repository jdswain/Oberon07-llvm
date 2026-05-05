MODULE ArcTests;
  IMPORT Arc, Modules, TestRunner;

  PROCEDURE TestBuild10*();
    VAR base: INTEGER;
  BEGIN
    Arc.Drop();
    base := Modules.LiveObjects();
    Arc.Build(10);
    IF (Modules.LiveObjects() = base + 10) & (Arc.Sum() = 55)
    THEN TestRunner.Pass ELSE TestRunner.Fail END;
    Arc.Drop()
  END TestBuild10;

  PROCEDURE TestRebuild*();
    VAR base: INTEGER;
  BEGIN
    Arc.Drop();
    base := Modules.LiveObjects();
    Arc.Build(10);
    Arc.Build(3);     (* must reclaim the prior 10-node chain *)
    IF (Modules.LiveObjects() = base + 3) & (Arc.Sum() = 6)
    THEN TestRunner.Pass ELSE TestRunner.Fail END;
    Arc.Drop()
  END TestRebuild;

  PROCEDURE TestDrop*();
    VAR base: INTEGER;
  BEGIN
    Arc.Drop();
    base := Modules.LiveObjects();
    Arc.Build(5);
    Arc.Drop();
    IF Modules.LiveObjects() = base THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestDrop;

END ArcTests.
