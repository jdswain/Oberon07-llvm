MODULE SimpleWhileTest;
IMPORT SYSTEM;

VAR i: INTEGER;

PROCEDURE Put(adr: LONGINT; x: CHAR);
BEGIN
  SYSTEM.PUT(0, adr, x)
END Put;

BEGIN
  i := 3;
  WHILE i > 0 DO
    Put(0C000H, CHR(65 + i)); (* Write 'D', 'C', 'B' *)
    i := i - 1
  END
END SimpleWhileTest.