MODULE ArrsTests;
  IMPORT Arrs, TestRunner;

  PROCEDURE TestInitial*();
  BEGIN
    (* Arrs body sets buf[0..2] to 10,20,30 *)
    IF (Arrs.Get(0) = 10) & (Arrs.Get(1) = 20) & (Arrs.Get(2) = 30)
    THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestInitial;

  PROCEDURE TestSumInitial*();
  BEGIN
    (* 10 + 20 + 30 = 60; remaining slots are 0 *)
    IF Arrs.Sum() = 60 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestSumInitial;

  PROCEDURE TestSetThenSum*();
  BEGIN
    Arrs.Set(7, 1000);
    IF Arrs.Sum() = 1060 THEN TestRunner.Pass ELSE TestRunner.Fail END;
    Arrs.Set(7, 0)  (* reset for next run *)
  END TestSetThenSum;

END ArrsTests.
