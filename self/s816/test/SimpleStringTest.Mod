MODULE SimpleStringTest;
  IMPORT SYSTEM;
  
  VAR
    str: ARRAY 6 OF CHAR;
    ch: CHAR;
    
  PROCEDURE PutChar(c: CHAR);
    CONST
      ACIA_DATA = 0C000H;
  BEGIN
    SYSTEM.PUT(0, ACIA_DATA, c);
  END PutChar;
  
BEGIN
  (* Initialize string manually *)
  str[0] := "H";  
  str[1] := "e";  
  str[2] := "l";  
  str[3] := "l";  
  str[4] := "o";  
  str[5] := 0X;   (* null terminator *)
  
  (* Test basic character operations *)
  ch := str[0];
  PutChar(ch);
  PutChar(str[1]);
  PutChar(str[4])
END SimpleStringTest.