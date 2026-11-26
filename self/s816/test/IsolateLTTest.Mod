MODULE IsolateLTTest;
   IMPORT SYSTEM;
    
   PROCEDURE PutChar(value: CHAR);
	  CONST
		 ACIA_DATA = 0C000H;
   BEGIN
      SYSTEM.PUT(0, ACIA_DATA, value);
   END PutChar;

   PROCEDURE TestLT(x, y: INTEGER; expected: BOOLEAN);
   BEGIN
      IF x < y THEN 
         PutChar('T')
      ELSE
         PutChar('F')
      END;
      IF expected THEN PutChar('Y') ELSE PutChar('N') END;
      PutChar(' ')
   END TestLT;

BEGIN
   (* Isolated test case: 10 < -5 should be FALSE *)
   (* Expected output: "FN " but currently outputs "TN " *)
   TestLT(10, -5, FALSE);
END IsolateLTTest.