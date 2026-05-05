MODULE StrPassTests;
  IMPORT StrPass, TestRunner;

  PROCEDURE TestFirstByteOfHi*();
  BEGIN
    (* "h" = 104 *)
    IF StrPass.FirstByteOfHi() = 104 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestFirstByteOfHi;

  PROCEDURE TestLengthOfHello*();
  BEGIN
    IF StrPass.LengthOfHello() = 5 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestLengthOfHello;

  PROCEDURE TestLength*();
    VAR s: ARRAY 16 OF CHAR;
  BEGIN
    s := "world!";
    IF StrPass.Length(s) = 6 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestLength;

  PROCEDURE TestFirstByte*();
    VAR s: ARRAY 4 OF CHAR;
  BEGIN
    s := "Z";
    IF StrPass.FirstByte(s) = 90 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestFirstByte;

END StrPassTests.
