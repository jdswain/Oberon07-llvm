MODULE ASCIITest;
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
  (* Test known ASCII values *)
  ch := 41X;   (* 'A' = 65 decimal = 41 hex *)
  PutChar(ch);
  
  ch := 42X;   (* 'B' = 66 decimal = 42 hex *)
  PutChar(ch);
  
  ch := 43X;   (* 'C' = 67 decimal = 43 hex *)  
  PutChar(ch);
  
  ch := 48X;   (* 'H' = 72 decimal = 48 hex *)
  PutChar(ch)
END ASCIITest.