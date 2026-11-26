MODULE CharTest;
  IMPORT SYSTEM;
  
  VAR
    ch: CHAR;
    
  PROCEDURE PutChar(c: CHAR);
    CONST
      ACIA_DATA = 0C000H;
  BEGIN
    SYSTEM.PUT(0, ACIA_DATA, c);
  END PutChar;
  
BEGIN
  ch := 48X;  (* 'H' = 72 decimal = 48H *)
  PutChar(ch)
END CharTest.