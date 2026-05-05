MODULE ShortTests;
  IMPORT Short, TestRunner;

  PROCEDURE TestNilShortCircuitAnd*();
    VAR p: Short.Box;
  BEGIN
    p := NIL;
    (* Must not deref NIL when p = NIL on the left of &. *)
    IF ~Short.IsZero(p) THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestNilShortCircuitAnd;

  PROCEDURE TestNilShortCircuitOr*();
    VAR p: Short.Box;
  BEGIN
    p := NIL;
    (* (p = NIL) OR (p.val >= 0) — must short-circuit on left. *)
    IF Short.NonNeg(p) THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestNilShortCircuitOr;

  PROCEDURE TestIsZero*();
    VAR p: Short.Box;
  BEGIN
    NEW(p); p.val := 0;
    IF Short.IsZero(p) THEN
      p.val := 7;
      IF ~Short.IsZero(p) THEN TestRunner.Pass ELSE TestRunner.Fail END
    ELSE TestRunner.Fail END
  END TestIsZero;

  PROCEDURE TestNonNeg*();
    VAR p: Short.Box;
  BEGIN
    NEW(p); p.val := 0;
    IF Short.NonNeg(p) THEN
      p.val := -5;
      IF ~Short.NonNeg(p) THEN
        p.val := 7;
        IF Short.NonNeg(p) THEN TestRunner.Pass ELSE TestRunner.Fail END
      ELSE TestRunner.Fail END
    ELSE TestRunner.Fail END
  END TestNonNeg;

  PROCEDURE TestBoth*();
  BEGIN
    IF (Short.Both(TRUE, FALSE, 5, -1) = 1)
     & (Short.Both(FALSE, TRUE, -1, -1) = 10)
     & (Short.Both(FALSE, FALSE, -1, -1) = 0)
     & (Short.Both(TRUE, FALSE, 5, 5) = 11)
    THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestBoth;

END ShortTests.
