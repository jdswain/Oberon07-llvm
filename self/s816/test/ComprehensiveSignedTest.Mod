MODULE ComprehensiveSignedTest;
   IMPORT SYSTEM;

   VAR
      a, b: INTEGER;
    
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

   PROCEDURE TestGE(x, y: INTEGER; expected: BOOLEAN);
   BEGIN
      IF x >= y THEN 
         PutChar("T")
      ELSE
         PutChar("F")
      END;
      IF expected THEN PutChar("Y") ELSE PutChar("N") END;
      PutChar(' ')
   END TestGE;

BEGIN
   (* Test signed comparisons with various values *)
   PutChar('L'); PutChar('T'); PutChar(':');
   TestLT(-5000, 1000, TRUE);     (* TY: -5 < 10 = TRUE *)
   TestLT(10, -5, FALSE);    (* FN: 10 < -5 = FALSE *)  
   TestLT(-32768, 32767, TRUE);   (* TY: most negative < most positive *)
   TestLT(32767, -32768, FALSE);  (* FN: most positive < most negative *)
   PutChar(0AX); (* newline *)

   PutChar('G'); PutChar('T'); PutChar(':');
   TestGT(-5, 10, FALSE);    (* FN: -5 > 10 = FALSE *)
   TestGT(10, -5, TRUE);     (* TY: 10 > -5 = TRUE *)
   TestGT(-32768, 32767, FALSE);  (* FN: most negative > most positive *)
   TestGT(32767, -32768, TRUE);   (* TY: most positive > most negative *)
   PutChar(0AX); (* newline *)

   PutChar('L'); PutChar('E'); PutChar(':');
   TestLE(-5, 10, TRUE);     (* TY: -5 <= 10 = TRUE *)
   TestLE(10, -5, FALSE);    (* FN: 10 <= -5 = FALSE *)
   TestLE(5, 5, TRUE);       (* TY: 5 <= 5 = TRUE *)
   TestLE(-32768, 32767, TRUE);   (* TY: most negative <= most positive *)
   PutChar(0AX); (* newline *)

   PutChar('G'); PutChar('E'); PutChar(':');
   TestGE(-5, 10, FALSE);    (* FN: -5 >= 10 = FALSE *)
   TestGE(10, -5, TRUE);     (* TY: 10 >= -5 = TRUE *)
   TestGE(5, 5, TRUE);       (* TY: 5 >= 5 = TRUE *)
   TestGE(32767, -32768, TRUE);   (* TY: most positive >= most negative *)
END ComprehensiveSignedTest.