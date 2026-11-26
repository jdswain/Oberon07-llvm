MODULE MinimalLETest;
   IMPORT SYSTEM;
    
   PROCEDURE PutChar(value: CHAR);
	  CONST
		 ACIA_DATA = 0C000H;
   BEGIN
      SYSTEM.PUT(0, ACIA_DATA, value);
   END PutChar;

BEGIN
   (* The failing LE test case: -5 <= 10 should be TRUE *)
   IF -5 <= 10 THEN 
      PutChar('T')  (* Correct - should execute *)
   ELSE
      PutChar('F')  (* Wrong - should not execute *)
   END
END MinimalLETest.