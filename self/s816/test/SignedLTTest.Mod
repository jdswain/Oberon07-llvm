MODULE SignedLTTest;
   IMPORT SYSTEM;

   VAR
      a, b: INTEGER;
    
   PROCEDURE PutChar(value: CHAR);
	  CONST
		 ACIA_DATA = 0C000H;
   BEGIN
      SYSTEM.PUT(0, ACIA_DATA, value);
   END PutChar;

BEGIN
   (* Test signed less than comparison *)
   a := -5;
   b := 10;
   IF a < b THEN 
      PutChar('Y')  (* Should print Y since -5 < 10 *)
   ELSE
      PutChar('N')
   END;
   
   (* Test edge case with overflow potential *)
   a := -32768;  (* Most negative 16-bit number *)
   b := 32767;   (* Most positive 16-bit number *)
   IF a < b THEN 
      PutChar('Y')  (* Should print Y since -32768 < 32767 *)
   ELSE
      PutChar('N')
   END
END SignedLTTest.