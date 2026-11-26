MODULE GTOverflowTest;
   IMPORT SYSTEM;
    
   PROCEDURE PutChar(value: CHAR);
	  CONST
		 ACIA_DATA = 0C000H;
   BEGIN
      SYSTEM.PUT(0, ACIA_DATA, value);
   END PutChar;

BEGIN
   (* GT overflow tests that are failing: *)
   (* -32768 > 32767 should be FALSE *)
   IF -32768 > 32767 THEN 
      PutChar('T')  (* Wrong - should not execute *)
   ELSE
      PutChar('F')  (* Correct - should execute *)
   END;
   
   (* 32767 > -32768 should be TRUE *)
   IF 32767 > -32768 THEN 
      PutChar('T')  (* Correct - should execute *)
   ELSE
      PutChar('F')  (* Wrong - should not execute *)
   END
END GTOverflowTest.