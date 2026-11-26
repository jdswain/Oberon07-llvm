MODULE PutHexTest;
   IMPORT SYSTEM;
	  
   CONST
      ACIA_DATA = 0C000H;
      
   VAR
	  v: INTEGER;
	  
   PROCEDURE PutChar(value: CHAR);
   BEGIN
      SYSTEM.PUT(0, ACIA_DATA, value);
   END PutChar;
   
   PROCEDURE PutHex(value: INTEGER);
      VAR
		 digit: INTEGER;
   BEGIN
	  IF value < 0 THEN
		 value := AND(value, 07FFFH);
		 PutChar('-');
	  END;

	  digit := LSR(value, 4);
      IF digit < 10 THEN
		 PutChar(CHR(digit + ORD('0')))
      ELSE
		 PutChar(CHR(digit - 10 + ORD('A')))
      END;

      digit := AND(value, 0FH);
      IF digit < 10 THEN
		 PutChar(CHR(digit + ORD('0')))
      ELSE
		 PutChar(CHR(digit - 10 + ORD('A')))
      END
   END PutHex;
   
   PROCEDURE NewLine();
   BEGIN
      SYSTEM.PUT(0, ACIA_DATA, 0AX);
   END NewLine;
   
BEGIN
      v := -12; PutHex(v); NewLine();
      v := -0FFH; PutHex(v); NewLine();
END PutHexTest.