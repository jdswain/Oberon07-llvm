MODULE FixedStringTest;
  IMPORT SYSTEM;
  
  VAR
    str: ARRAY 10 OF CHAR;
    ch1, ch2: CHAR;
    i: INTEGER;
    
  PROCEDURE PutChar(c: CHAR);
    CONST
      ACIA_DATA = 0C000H;
  BEGIN
    SYSTEM.PUT(0, ACIA_DATA, c);
  END PutChar;
  
BEGIN
  (* Test various character constant formats *)
  ch1 := 48X;   (* 'H' = 72 decimal = 48 hex *)
  ch2 := 65X;   (* 'e' = 101 decimal = 65 hex *)
  
  (* Initialize string with hex character constants only *)
  str[0] := 48X;   (* 'H' = 72 decimal = 48 hex *)
  str[1] := 65X;   (* 'e' = 101 decimal = 65 hex *)
  str[2] := 6CX;   (* 'l' = 108 decimal = 6C hex *)
  str[3] := 6CX;   (* 'l' *)
  str[4] := 6FX;   (* 'o' = 111 decimal = 6F hex *)
  str[5] := 20X;   (* ' ' = 32 decimal = 20 hex (space) *)
  str[6] := 57X;   (* 'W' = 87 decimal = 57 hex *)
  str[7] := 6FX;   (* 'o' *)
  str[8] := 72X;   (* 'r' = 114 decimal = 72 hex *)
  str[9] := 0X;    (* null terminator *)
  
  (* Output individual characters *)
  PutChar(ch1);
  PutChar(ch2);
  
  (* Output string character by character * )
  i := 0;
  WHILE (i < 10) & (str[i] # 0X) DO
    PutChar(str[i]);
    i := i + 1
  END
  *)
END FixedStringTest.