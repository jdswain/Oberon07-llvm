MODULE LETest;
   IMPORT SYSTEM;
    
   PROCEDURE PutChar(value: CHAR);
	  CONST
		 ACIA_DATA = 0C000H;
   BEGIN
      SYSTEM.PUT(0, ACIA_DATA, value);
   END PutChar;

   PROCEDURE TestLE(x, y: INTEGER; expected: BOOLEAN);
   BEGIN
      IF x <= y THEN 
         PutChar('T')
      ELSE
         PutChar('F')
      END;
      IF expected THEN PutChar('Y') ELSE PutChar('N') END;
      PutChar(' ')
   END TestLE;

BEGIN
   (* LE test cases *)
   TestLE(-5, 10, TRUE);     (* TY: -5 <= 10 = TRUE *)
   TestLE(10, -5, FALSE);    (* FN: 10 <= -5 = FALSE *)
   TestLE(5, 5, TRUE);       (* TY: 5 <= 5 = TRUE *)
   TestLE(-32768, 32767, TRUE);   (* TY: most negative <= most positive *)
END LETest.