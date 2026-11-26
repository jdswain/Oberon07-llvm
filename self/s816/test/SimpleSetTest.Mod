MODULE SimpleSetTest;
   IMPORT SYSTEM;

   VAR
      s: SET;
    
   PROCEDURE PutChar(value: CHAR);
	  CONST
		 ACIA_DATA = 0C000H;
   BEGIN
      SYSTEM.PUT(0, ACIA_DATA, value);
   END PutChar;

BEGIN
   (* Test simplest SET operation *)
   s := {5};  (* Set containing just element 5 *)
   
   IF 5 IN s THEN 
      PutChar('Y')  (* Should execute *)
   ELSE
      PutChar('N')  
   END;
   
   IF 3 IN s THEN 
      PutChar('Y')  
   ELSE
      PutChar('N')  (* Should execute *)
   END
END SimpleSetTest.