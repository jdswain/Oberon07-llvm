MODULE SuperTests;
  IMPORT Super, TestRunner;

  PROCEDURE TestSuperChain*();
    VAR a: Super.A;
  BEGIN
    (* C.Describe -> B.Describe (immediate base, not A) -> A.Describe *)
    a := Super.NewC(0);
    IF a.Describe() = 123 THEN TestRunner.Pass ELSE TestRunner.Fail END;
    a := Super.NewB(0);
    IF a.Describe() = 12 THEN TestRunner.Pass ELSE TestRunner.Fail END;
    a := Super.NewA(0);
    IF a.Describe() = 1 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestSuperChain;

  PROCEDURE TestSuperNonOverridden*();
    VAR b: Super.B;
  BEGIN
    b := Super.NewB(5);
    IF b.TagPlus() = 6 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestSuperNonOverridden;

  PROCEDURE TestSuperStatement*();
    VAR a: Super.A;
  BEGIN
    (* B.Bump runs A.Bump via SUPER, then increments again *)
    a := Super.NewB(5);
    a.Bump();
    IF a.tag = 7 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestSuperStatement;

END SuperTests.
