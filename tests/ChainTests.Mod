MODULE ChainTests;
  IMPORT Chain, TestRunner;

  PROCEDURE TestAll*();
  BEGIN
    IF Chain.All(TRUE, TRUE, TRUE)
     & ~Chain.All(TRUE, TRUE, FALSE)
     & ~Chain.All(TRUE, FALSE, TRUE)
     & ~Chain.All(FALSE, TRUE, TRUE)
    THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestAll;

  PROCEDURE TestAny*();
  BEGIN
    IF ~Chain.Any(FALSE, FALSE, FALSE)
     & Chain.Any(TRUE, FALSE, FALSE)
     & Chain.Any(FALSE, TRUE, FALSE)
     & Chain.Any(FALSE, FALSE, TRUE)
    THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestAny;

  PROCEDURE TestMix*();
  BEGIN
    IF Chain.Mix(TRUE, FALSE, TRUE)
     & Chain.Mix(FALSE, TRUE, TRUE)
     & ~Chain.Mix(TRUE, FALSE, FALSE)
     & ~Chain.Mix(FALSE, FALSE, TRUE)
     & ~Chain.Mix(FALSE, FALSE, FALSE)
    THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestMix;

END ChainTests.
