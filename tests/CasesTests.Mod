MODULE CasesTests;
  IMPORT Cases, TestRunner;

  PROCEDURE TestDay*();
    VAR ok: BOOLEAN;
  BEGIN
    ok := (Cases.Day(0) = 100)
        & (Cases.Day(1) = 200) & (Cases.Day(2) = 200) & (Cases.Day(3) = 200)
        & (Cases.Day(4) = 300) & (Cases.Day(5) = 300) & (Cases.Day(6) = 300)
        & (Cases.Day(7) = 400)
        & (Cases.Day(8) = 999) & (Cases.Day(-1) = 999);
    IF ok THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestDay;

  PROCEDURE TestVowelLower*();
  BEGIN
    IF    Cases.Vowel("a") & Cases.Vowel("e") & Cases.Vowel("i")
        & Cases.Vowel("o") & Cases.Vowel("u")
    THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestVowelLower;

  PROCEDURE TestVowelUpper*();
  BEGIN
    IF    Cases.Vowel("A") & Cases.Vowel("E") & Cases.Vowel("I")
        & Cases.Vowel("O") & Cases.Vowel("U")
    THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestVowelUpper;

  PROCEDURE TestVowelConsonant*();
  BEGIN
    IF    ~Cases.Vowel("b") & ~Cases.Vowel("c") & ~Cases.Vowel("z")
        & ~Cases.Vowel("B") & ~Cases.Vowel("Z")
        & ~Cases.Vowel("1")
    THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestVowelConsonant;

  PROCEDURE TestNoElse*();
  BEGIN
    IF (Cases.NoElse(1) = 10) & (Cases.NoElse(2) = 20)
     & (Cases.NoElse(3) = -1) & (Cases.NoElse(0) = -1)
    THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestNoElse;

END CasesTests.
