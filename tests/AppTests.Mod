MODULE AppTests;
  IMPORT App, Util, TestRunner;

  PROCEDURE TestQuad*();
  BEGIN
    IF App.Quad(7) = 28 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestQuad;

  PROCEDURE TestUtilCounterInitial*();
  BEGIN
    (* Util body sets counter := 100 once via the init guard. *)
    IF Util.counter >= 100 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestUtilCounterInitial;

  PROCEDURE TestBumpTwice*();
    VAR before: INTEGER;
  BEGIN
    before := Util.counter;
    App.BumpTwice;
    IF (Util.counter = before + 2) & (App.GetCounter() = before + 2)
    THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestBumpTwice;

END AppTests.
