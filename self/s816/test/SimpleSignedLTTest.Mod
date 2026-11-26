MODULE SimpleSignedLTTest;
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
   (* Simple test: -5 < 10 should be TRUE *)
   a := -5;
   b := 10;
   IF a < b THEN 
      PutChar('Y')  (* Should execute this *)
   ELSE
      PutChar('N')
   END
END SimpleSignedLTTest.