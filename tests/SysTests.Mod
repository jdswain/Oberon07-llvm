MODULE SysTests;
  IMPORT SYSTEM, TestRunner;

  PROCEDURE TestAsl*();
  BEGIN
    IF (ASL(1, 4) = 16) & (ASL(01234H, 8) = 0123400H)
    THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestAsl;

  PROCEDURE TestLsr*();
  BEGIN
    (* LSR is logical (zero-filled), not arithmetic. *)
    IF (LSR(080000000H, 1) = 040000000H) & (LSR(0FFH, 4) = 0FH)
    THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestLsr;

  PROCEDURE TestRol*();
  BEGIN
    (* Rotate-left by 4 of 0x12345678 → 0x23456781 *)
    IF (ROL(012345678H, 4) = 023456781H)
        & (ROL(0DEADBEEFH, 0) = 0DEADBEEFH)
    THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestRol;

  PROCEDURE TestUml*();
  BEGIN
    (* Low-half of 0xFFFFFFFF * 2 = 0x1FFFFFFFE → 0xFFFFFFFE *)
    IF (UML(3, 7) = 21) & (UML(0FFFFFFFFH, 2) = 0FFFFFFFEH)
    THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestUml;

  PROCEDURE TestPutGet*();
    VAR cell, out: INTEGER;
        a: LONGINT;
  BEGIN
    cell := 0;
    a := SYSTEM.ADR(cell);
    SYSTEM.PUT(a, 12345678);
    SYSTEM.GET(a, out);
    IF out = 12345678 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestPutGet;

  PROCEDURE TestCopy*();
    VAR src, dst: ARRAY 4 OF INTEGER;
        sa, da: LONGINT;
        i, sum: INTEGER;
  BEGIN
    src[0] := 100; src[1] := 200; src[2] := 300; src[3] := 400;
    dst[0] := 0; dst[1] := 0; dst[2] := 0; dst[3] := 0;
    sa := SYSTEM.ADR(src);
    da := SYSTEM.ADR(dst);
    SYSTEM.COPY(sa, da, 16);
    sum := 0;
    FOR i := 0 TO 3 DO sum := sum + dst[i] END;
    IF sum = 1000 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestCopy;

END SysTests.
