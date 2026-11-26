MODULE MinimalLTTest;
   IMPORT SYSTEM;
    
   PROCEDURE PutChar(value: CHAR);
	  CONST
		 ACIA_DATA = 0C000H;
   BEGIN
      SYSTEM.PUT(0, ACIA_DATA, value);
   END PutChar;

BEGIN
   (* Minimal test: just the comparison without procedure call *)
   IF 10 < -5 THEN 
      PutChar('T')  (* Wrong - should not execute *)
   ELSE
      PutChar('F')  (* Correct - should execute *)
   END
END MinimalLTTest.