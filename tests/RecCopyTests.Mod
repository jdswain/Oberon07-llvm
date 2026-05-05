MODULE RecCopyTests;
  IMPORT RecCopy, TestRunner;

  PROCEDURE TestCopy*();
    VAR a, b: RecCopy.Pt;
  BEGIN
    a.x := 1; a.y := 2; a.z := 3;
    b.x := 0; b.y := 0; b.z := 0;
    RecCopy.Copy(b, a);
    IF (b.x = 1) & (b.y = 2) & (b.z = 3)
    THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestCopy;

END RecCopyTests.
