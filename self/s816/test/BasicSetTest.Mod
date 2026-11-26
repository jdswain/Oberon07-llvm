MODULE BasicSetTest;
   IMPORT SYSTEM;

   VAR
      s1, s2: SET;
    
   PROCEDURE PutChar(value: CHAR);
	  CONST
		 ACIA_DATA = 0C000H;
   BEGIN
      SYSTEM.PUT(0, ACIA_DATA, value);
   END PutChar;

BEGIN
   (* Test basic SET creation and membership *)
   s1 := {1, 3, 5};
   
   (* Test IN operator *)
   IF 1 IN s1 THEN 
      PutChar('T')  (* Should execute - 1 is in set *)
   ELSE
      PutChar('F')
   END;
   
   IF 2 IN s1 THEN 
      PutChar('T')
   ELSE
      PutChar('F')  (* Should execute - 2 is not in set *)
   END;
   
   (* Test set union *)
   s2 := {2, 4};
   s1 := s1 + s2;  (* Union operation *)
   
   IF 2 IN s1 THEN 
      PutChar('T')  (* Should execute - 2 now in union *)
   ELSE
      PutChar('F')
   END;
   
   PutChar(' ');  (* Space separator *)
   
   (* Test empty set *)
   s2 := {};
   IF 0 IN s2 THEN 
      PutChar('T')
   ELSE
      PutChar('F')  (* Should execute - empty set *)
   END
END BasicSetTest.