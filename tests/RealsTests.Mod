MODULE RealsTests;
  IMPORT Reals, TestRunner;

  PROCEDURE near(a, b: REAL): BOOLEAN;
    VAR d: REAL;
  BEGIN
    d := a - b;
    IF d < 0.0 THEN d := -d END;
    RETURN d < 0.00001
  END near;

  PROCEDURE TestAdd*();
  BEGIN IF near(Reals.Add(1.5, 2.25), 3.75) THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestAdd;

  PROCEDURE TestSub*();
  BEGIN IF near(Reals.Sub(5.0, 1.5), 3.5) THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestSub;

  PROCEDURE TestMul*();
  BEGIN IF near(Reals.Mul(2.5, 4.0), 10.0) THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestMul;

  PROCEDURE TestDiv*();
  BEGIN IF near(Reals.Div(7.0, 2.0), 3.5) THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestDiv;

  PROCEDURE TestNeg*();
  BEGIN IF near(Reals.Neg(3.25), -3.25) THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestNeg;

  PROCEDURE TestCmp*();
  BEGIN
    IF (Reals.Cmp(1.0, 2.0) = -1) & (Reals.Cmp(2.0, 1.0) = 1) & (Reals.Cmp(1.5, 1.5) = 0)
    THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestCmp;

  PROCEDURE TestFromInt*();
  BEGIN IF near(Reals.FromInt(42), 42.0) THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestFromInt;

  PROCEDURE TestToInt*();
  BEGIN
    (* FLOOR rounds toward -∞ : 3.7 → 3 ; -3.7 → -4 *)
    IF (Reals.ToInt(3.7) = 3) & (Reals.ToInt(-3.7) = -4)
    THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestToInt;

  PROCEDURE TestSumReciprocals*();
  BEGIN
    (* 1 + 1/2 + 1/3 + 1/4 + 1/5 ≈ 2.2833333 *)
    IF near(Reals.SumReciprocals(5), 2.2833333) THEN TestRunner.Pass
    ELSE TestRunner.Fail END
  END TestSumReciprocals;

END RealsTests.
