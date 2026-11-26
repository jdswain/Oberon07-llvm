MODULE DebugSignedLTTest;
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
   (* Debug test: -5 < 10 should be TRUE *)
   a := -5;
   b := 10;
   PutChar('S'); PutChar('T'); PutChar('A'); PutChar('R'); PutChar('T'); PutChar(' ');
   IF a < b THEN 
      PutChar('T'); PutChar('R'); PutChar('U'); PutChar('E')  (* Should execute this *)
   ELSE
      PutChar('F'); PutChar('A'); PutChar('L'); PutChar('S'); PutChar('E')
   END;
   PutChar(' '); PutChar('E'); PutChar('N'); PutChar('D')
END DebugSignedLTTest.