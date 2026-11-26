MODULE WhileTest;
IMPORT SYSTEM;

VAR 
  i: INTEGER;
    
PROCEDURE PutByte(value: BYTE);
CONST
  ACIA_DATA = 0C000H;
BEGIN
  SYSTEM.PUT(0, ACIA_DATA, value);
END PutByte;

PROCEDURE PutNum(n: INTEGER);
BEGIN
  PutByte(30H + n);  (* Convert to ASCII digit *)
END PutNum;

BEGIN
  PutByte(57H);  (* W *)
  PutByte(3AH);  (* : *)
  
  (* Simple WHILE loop *)
  i := 1;
  WHILE i <= 3 DO
    PutNum(i);
    PutByte(22H);  (* space *)
    i := i + 1;
  END;
  
  PutByte(0AH);  (* newline *)
END WhileTest.
