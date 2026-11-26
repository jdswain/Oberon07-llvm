MODULE ComprehensiveArrayTest;
   IMPORT SYSTEM;

   VAR
      str: ARRAY 15 OF CHAR;
    
   PROCEDURE PutChar(value: CHAR);
	  CONST
		 ACIA_DATA = 0C000H;
   BEGIN
      SYSTEM.PUT(0, ACIA_DATA, value);
   END PutChar;

   PROCEDURE WriteString(s: ARRAY OF CHAR);
      VAR i: INTEGER;
   BEGIN i := 0;
      WHILE s[i] >= " " DO PutChar(s[i]); INC(i) END
   END WriteString;
   
   PROCEDURE Println(str: ARRAY OF CHAR);
	  VAR
		 i: INTEGER;
   BEGIN
	  i := 0;
	  (* Output string character by character *)
	  WHILE (str[i] # 0X) DO
		 PutChar(str[i]); i := i + 1
	  END;
	  PutChar(0AX);  (* newline *)
   END Println;
   
BEGIN
   str := "Hello World";
   WriteString(str);
END ComprehensiveArrayTest.
