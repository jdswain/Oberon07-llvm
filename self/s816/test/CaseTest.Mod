MODULE CaseTest;
IMPORT SYSTEM;

VAR 
  i: INTEGER;
    
PROCEDURE PutByte(value: BYTE);
CONST
  ACIA_DATA = 0C000H;
BEGIN
  SYSTEM.PUT(0, ACIA_DATA, value);
END PutByte;

PROCEDURE PutChar(ch: CHAR);
BEGIN
  PutByte(ORD(ch));
END PutChar;

BEGIN
  PutChar("C");
  PutChar(":");
  
  (* Simple CASE statement *)
  FOR i := 1 TO 4 DO
    CASE i OF
      1: PutChar("A");
    | 2: PutChar("B");
    | 3: PutChar("C");
    ELSE
      PutChar("?");
    END;
    PutChar(" ");
  END;
  
  PutChar(CHR(10));  (* newline *)
END CaseTest.
