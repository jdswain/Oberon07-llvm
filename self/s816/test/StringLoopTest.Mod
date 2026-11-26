MODULE StringLoopTest;
   IMPORT SYSTEM;
    
   PROCEDURE PutChar(value: CHAR);
	  CONST
		 ACIA_DATA = 0C000H;
   BEGIN
      SYSTEM.PUT(0, ACIA_DATA, value);
   END PutChar;

   PROCEDURE TestLoop(s: ARRAY OF CHAR);
      VAR i: INTEGER;
   BEGIN
      i := 0;
      (* This is the problematic pattern from StringTest *)
      WHILE (s[i] # 0X) DO
         PutChar(s[i]); 
         i := i + 1
      END
   END TestLoop;

BEGIN
   TestLoop("TEST")
END StringLoopTest.