MODULE OverflowLTTest;
   IMPORT SYSTEM;
    
   PROCEDURE PutChar(value: CHAR);
	  CONST
		 ACIA_DATA = 0C000H;
   BEGIN
      SYSTEM.PUT(0, ACIA_DATA, value);
   END PutChar;

BEGIN
   (* Overflow test: -32760 < 32760 should be TRUE *)
   IF -32760 < 32760 THEN 
      PutChar('T')  (* Correct - should execute *)
   ELSE
      PutChar('F')  (* Wrong - should not execute *)
   END
END OverflowLTTest.