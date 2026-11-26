MODULE StringTest;
   IMPORT SYSTEM;
	  
   CONST
	  ACIA_DATA = 0C000H;
	  
   TYPE
	  String = ARRAY 250 OF CHAR;
	  
   VAR
	  str: String;
	  x: INTEGER;
	  y: ARRAY 10 OF CHAR;
	  
   PROCEDURE NewLine*;
   BEGIN
	  SYSTEM.PUT(0, ACIA_DATA, 0AX);
   END NewLine;
   
   PROCEDURE PutChar*(value: CHAR);
   BEGIN
	  SYSTEM.PUT(0, ACIA_DATA, value);
   END PutChar;

   PROCEDURE Println*(VAR str: ARRAY OF CHAR);
	  VAR
		 i: INTEGER;
   BEGIN
	  i := 0;
	  x := LEN(str);
	  IF x = 250 THEN
		 PutChar('T');
	  ELSE
		 PutChar('F');
	  END;

	  str[1] := 'T';
	  
	  (* Output string character by character *)
	  WHILE (str[i] # 0X) DO
		 PutChar(str[i]); i := i + 1
	  END;
   END Println;
   
BEGIN
   y[0] := 'A';
   y[1] := 'B';
   y[2] := 'C';
   y[3] := 00X;
   Println(y);
   str := "String Test";
   Println(str); NewLine();
END StringTest.
