MODULE RepeatTest;
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
  PutByte(52H);  (* R *)
  PutByte(3AH);  (* : *)
  
  (* Simple REPEAT loop *)
  i := 1;
  REPEAT
    PutNum(i);
    PutByte(20H);  (* space *)
    i := i + 1;
  UNTIL i > 3;
  
  PutByte(0AH);  (* newline *)
END RepeatTest.
