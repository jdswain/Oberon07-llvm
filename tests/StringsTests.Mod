MODULE StringsTests;
  IMPORT Strings, TestRunner;

  PROCEDURE TestGreet*();
  BEGIN
    Strings.Greet();
    IF Strings.greeting = "hello" THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestGreet;

  PROCEDURE TestEcho*();
    VAR buf: ARRAY 16 OF CHAR;
  BEGIN
    Strings.Echo(buf);
    IF buf = "echoed" THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestEcho;

  PROCEDURE TestEqGreeting*();
    VAR same, diff: ARRAY 16 OF CHAR;
  BEGIN
    (* greeting is "hello" by now (TestGreet runs before this). *)
    Strings.Greet();
    same := "hello";
    diff := "world";
    IF Strings.EqGreeting(same) & ~Strings.EqGreeting(diff)
    THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestEqGreeting;

  PROCEDURE TestFirstChar*();
  BEGIN
    IF Strings.FirstChar() = "A" THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestFirstChar;

END StringsTests.
