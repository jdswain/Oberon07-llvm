MODULE GETest;
   IMPORT SYSTEM;
    
   PROCEDURE PutChar(value: CHAR);
	  CONST
		 ACIA_DATA = 0C000H;
   BEGIN
      SYSTEM.PUT(0, ACIA_DATA, value);
   END PutChar;

   PROCEDURE TestGE(x, y: INTEGER; expected: BOOLEAN);
   BEGIN
      IF x >= y THEN 
         PutChar('T')
      ELSE
         PutChar('F')
      END;
      IF expected THEN PutChar('Y') ELSE PutChar('N') END;
      PutChar(' ')
   END TestGE;

BEGIN
   (* GE test cases *)
   TestGE(-5, 10, FALSE);    (* FN: -5 >= 10 = FALSE *)
   TestGE(10, -5, TRUE);     (* TY: 10 >= -5 = TRUE *)
   TestGE(5, 5, TRUE);       (* TY: 5 >= 5 = TRUE *)
   TestGE(32767, -32768, TRUE);   (* TY: most positive >= most negative *)
END GETest.