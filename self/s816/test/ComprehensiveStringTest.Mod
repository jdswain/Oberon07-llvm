MODULE ComprehensiveStringTest;
   IMPORT SYSTEM;

   VAR
      str: ARRAY 10 OF CHAR;
      ch1, ch2: CHAR;
      i: INTEGER;
    
   PROCEDURE PutChar(value: CHAR);
	  CONST
		 ACIA_DATA = 0C000H;
   BEGIN
      SYSTEM.PUT(0, ACIA_DATA, value);
   END PutChar;

BEGIN
  ch1 := 48X;   (* 'H' = 72 decimal = 48 hex *)
  ch2 := 65X;   (* 'e' = 101 decimal = 65 hex *)

  (* Initialize string with character constants *)
  str[0] := "H";   (* 'H' *)
  str[1] := "e";   (* 'e' *)
  str[2] := "l";   (* 'l' = 108 decimal = 6C hex *)
  str[3] := "l";   (* 'l' *)
  str[4] := "o";   (* 'o' = 111 decimal = 6F hex *)
  str[5] := " ";   (* ' ' = 32 decimal = 20 hex (space) *)
  str[6] := "W";   (* 'W' = 87 decimal = 57 hex *)
  str[7] := "o";   (* 'o' *)
  str[8] := "r";   (* 'r' = 114 decimal = 72 hex *)
  str[9] := 0X;    (* null terminator *)

  (* Output string character by character *)
  WHILE (str[i] # 0X) DO
     PutChar(str[i]); i := i + 1
  END;

  PutChar(0AX);  (* newline *)
    
 END ComprehensiveStringTest.
