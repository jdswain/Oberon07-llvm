MODULE MultTest;
   IMPORT SYSTEM;

   CONST
	  ACIA_DATA = 0C000H;
	  
   VAR
	  x,y,z: INTEGER;

	  
   PROCEDURE NewLine();
   BEGIN
	  SYSTEM.PUT(0, ACIA_DATA, 0AX);
   END NewLine;
   
   PROCEDURE PutChar(value: CHAR);
   BEGIN
	  SYSTEM.PUT(0, ACIA_DATA, value);
   END PutChar;

BEGIN
   y := 10;
   z := 6;
   x := y * z;
   IF x = 60 THEN
	  PutChar('P');
   ELSE
	  PutChar('F');
   END;
   NewLine();
END MultTest.
