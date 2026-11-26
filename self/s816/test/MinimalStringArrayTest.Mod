MODULE MinimalStringArrayTest;
   IMPORT SYSTEM;
    
   PROCEDURE PutChar(value: CHAR);
	  CONST
		 ACIA_DATA = 0C000H;
   BEGIN
      SYSTEM.PUT(0, ACIA_DATA, value);
   END PutChar;

   PROCEDURE TestString(s: ARRAY OF CHAR);
   BEGIN
      (* Just access the first character - this should not fail *)
      IF s[0] = "S" THEN 
         PutChar('Y')
      ELSE
         PutChar('N')
      END
   END TestString;

BEGIN
   TestString("STRING")
END MinimalStringArrayTest.