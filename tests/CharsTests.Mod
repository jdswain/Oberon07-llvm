MODULE CharsTests;
  IMPORT Chars, TestRunner;

  (* CHR(INTEGER var) passed directly as a CHAR argument — the exact shape
     that produced an i32-into-i8 call and failed IR verification. *)
  PROCEDURE TestChrArgFromInt* ();
    VAR i: INTEGER;
  BEGIN
    i := 65;
    IF Chars.Code(CHR(i)) = 65 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestChrArgFromInt;

  PROCEDURE TestChrArgFromByte* ();
    VAR b: BYTE;
  BEGIN
    b := 66;
    IF Chars.Code(CHR(b)) = 66 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestChrArgFromByte;

  PROCEDURE TestChrArgExpr* ();
  BEGIN
    IF Chars.Echo(CHR(ORD("A") + 2)) = "C" THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestChrArgExpr;

  (* CHR narrows to the low byte: CHR(141H) = CHR(41H) = "A". *)
  PROCEDURE TestChrLowByte* ();
    VAR i: INTEGER;
  BEGIN
    i := 141H;
    IF Chars.Code(CHR(i)) = 41H THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestChrLowByte;

  PROCEDURE TestDigit* ();
  BEGIN
    IF (Chars.Digit(3) = "3") & (Chars.Digit(0) = "0") THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestDigit;

END CharsTests.
