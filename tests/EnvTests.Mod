MODULE EnvTests;
  IMPORT Env, TestRunner;

  (* The host binary (testhost) was invoked from TestHost's main(). At
     a minimum argv[0] is set — that's the program path the OS handed
     us. Tests below probe the conventional invariants without
     assuming any particular argv string. *)

  PROCEDURE TestArgCountAtLeastOne*();
  BEGIN
    IF Env.ArgCount() >= 1 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestArgCountAtLeastOne;

  PROCEDURE TestArgZeroNonEmpty*();
    VAR s: ARRAY 256 OF CHAR;
  BEGIN
    s[0] := 0X;
    Env.Arg(0, s);
    (* program path on macOS / Linux is never the empty string *)
    IF s[0] # 0X THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestArgZeroNonEmpty;

  PROCEDURE TestOutOfRangeIsEmpty*();
    VAR s: ARRAY 64 OF CHAR; n: INTEGER;
  BEGIN
    n := Env.ArgCount();
    s[0] := "X";  (* sentinel — Arg should overwrite to 0X *)
    Env.Arg(n + 100, s);
    IF s[0] = 0X THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestOutOfRangeIsEmpty;

  PROCEDURE TestNegativeIsEmpty*();
    VAR s: ARRAY 64 OF CHAR;
  BEGIN
    s[0] := "X";
    Env.Arg(-1, s);
    IF s[0] = 0X THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestNegativeIsEmpty;

  PROCEDURE TestSmallBufferTruncates*();
    VAR s: ARRAY 4 OF CHAR; i: INTEGER; allFitOrOk: BOOLEAN;
  BEGIN
    (* Buffer of 4 = 3 chars + terminator. argv[0] is always longer than
       3 bytes for any real program path, so we expect strict truncation
       with a 0X at index 3 and no overrun. *)
    FOR i := 0 TO 3 DO s[i] := 0FFX END;
    Env.Arg(0, s);
    allFitOrOk := s[3] = 0X;
    IF allFitOrOk THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestSmallBufferTruncates;

END EnvTests.
