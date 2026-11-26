MODULE SpecificLTTest;
   IMPORT SYSTEM;

   VAR
      result: BOOLEAN;
    
   PROCEDURE PutChar(value: CHAR);
	  CONST
		 ACIA_DATA = 0C000H;
   BEGIN
      SYSTEM.PUT(0, ACIA_DATA, value);
   END PutChar;

BEGIN
   PutChar('A');
   (* Test case 1: 10 < -5 should be FALSE *)
   result := 10 < -5;
   IF result THEN 
      PutChar('T')  (* Wrong - should not execute *)
   ELSE
      PutChar('F')  (* Correct - should execute *)
   END;
   
   PutChar('B'); 
   (* Test case 2: 32767 < -32768 should be FALSE *)
   result := 32767 < -32768;
   IF result THEN 
      PutChar('T')  (* Wrong - should not execute *)
   ELSE
      PutChar('F')  (* Correct - should execute *)
   END;
   
   PutChar('C')
END SpecificLTTest.