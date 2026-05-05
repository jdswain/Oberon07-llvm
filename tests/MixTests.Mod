MODULE MixTests;
  IMPORT Mix, TestRunner;

  PROCEDURE TestTotalData*();
  BEGIN
    (* data initialised to 10,20,30,40,50 by Mix body — sum 150 *)
    IF Mix.TotalData() = 150 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestTotalData;

END MixTests.
