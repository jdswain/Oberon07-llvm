MODULE IsolateGTTest;
   IMPORT SYSTEM;
    
   PROCEDURE PutChar(value: CHAR);
	  CONST
		 ACIA_DATA = 0C000H;
   BEGIN
      SYSTEM.PUT(0, ACIA_DATA, value);
   END PutChar;

   PROCEDURE TestGT(x, y: INTEGER; expected: BOOLEAN);
   BEGIN
      IF x > y THEN 
         PutChar('T')
      ELSE
         PutChar('F')
      END;
      IF expected THEN PutChar('Y') ELSE PutChar('N') END;
      PutChar(' ')
   END TestGT;

BEGIN
   (* Isolated failing GT test case: -5 > 10 should be FALSE *)
   (* Expected output: "FN " but likely outputs something else *)
   TestGT(-5, 10, FALSE);
END IsolateGTTest.