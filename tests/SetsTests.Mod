MODULE SetsTests;
  IMPORT Sets, TestRunner, SYSTEM;

  PROCEDURE eq(s: SET; want: INTEGER): BOOLEAN;
    VAR i: INTEGER;
  BEGIN
    i := SYSTEM.VAL(INTEGER, s);
    RETURN i = want
  END eq;

  PROCEDURE TestEmpty*();
  BEGIN IF eq(Sets.Empty(), 0) THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestEmpty;

  PROCEDURE TestSingle*();
  BEGIN IF eq(Sets.Single(), 8) THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestSingle;

  PROCEDURE TestRange*();
  BEGIN IF eq(Sets.Range(), 03CH) THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestRange;

  PROCEDURE TestMixed*();
  BEGIN IF eq(Sets.Mixed(), 4E9H) THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestMixed;

  PROCEDURE TestFullByte*();
  BEGIN IF eq(Sets.FullByte(), 0FFH) THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestFullByte;

  PROCEDURE TestUnion*();
  BEGIN IF eq(Sets.Union(), 0EFH) THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestUnion;

  PROCEDURE TestIntersect*();
  BEGIN IF eq(Sets.Intersect(), 0F8H) THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestIntersect;

  PROCEDURE TestDiff*();
  BEGIN IF eq(Sets.Diff(), 0E3H) THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestDiff;

  PROCEDURE TestSym*();
  BEGIN IF eq(Sets.Sym(), 033H) THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestSym;

  PROCEDURE TestInTest*();
  BEGIN
    IF Sets.InTest(0) & Sets.InTest(2) & Sets.InTest(3)
        & Sets.InTest(7) & Sets.InTest(9)
        & ~Sets.InTest(4) & ~Sets.InTest(5) & ~Sets.InTest(20)
    THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestInTest;

  PROCEDURE TestInclExcl*();
  BEGIN IF eq(Sets.InclExcl(), 402H) THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestInclExcl;

END SetsTests.
