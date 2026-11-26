(* There is currently a bug WITH the IF statement and booleans? This test IS TO help debug it
*)

MODULE NegTest;
   IMPORT SYSTEM;
	  
   CONST
      ACIA_DATA = 0C000H;
      
   VAR
	  neg: BOOLEAN;
	  v: INTEGER;
	  
   PROCEDURE PutChar(value: CHAR);
   BEGIN
      SYSTEM.PUT(0, ACIA_DATA, value);
   END PutChar;
   
BEGIN
   v := 10;
   v := -v;
   (*neg := v < 0;*)
   IF v < 0 THEN
	  PutChar('-');
   END;
   PutChar('E');
END NegTest.