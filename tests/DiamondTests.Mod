MODULE DiamondTests;
  IMPORT Diamond, A, B, Counter, TestRunner;

  PROCEDURE TestInitGuard*();
  BEGIN
    (* Diamond imports A, B, Counter. A and B both import Counter.
       Counter init runs once (sets n := 0). A's body adds 100;
       B's body adds 1000. If the init guard works, the total is 1100
       — not 0+100+0+1000 from a re-run. *)
    IF Counter.n >= 1100 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestInitGuard;

  PROCEDURE TestTouches*();
    VAR before: INTEGER;
  BEGIN
    before := Counter.n;
    A.Touch;
    B.Touch;
    IF Counter.n = before + 2 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestTouches;

  PROCEDURE TestDiamondGet*();
  BEGIN
    IF Diamond.Get() = Counter.n THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestDiamondGet;

END DiamondTests.
