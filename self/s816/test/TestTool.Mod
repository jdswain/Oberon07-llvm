MODULE TestTool;   (* output through Out, the serial port *)
   IMPORT Out;
	  
   TYPE
	  String = ARRAY 250 OF CHAR;
	  
   VAR
	  str: String;
	  
   PROCEDURE NewLine*;
   BEGIN
	  Out.Ln
   END NewLine;
   
   PROCEDURE PutChar*(value: CHAR);
   BEGIN
	  Out.Char(value)
   END PutChar;

   PROCEDURE Println*(VAR str: ARRAY OF CHAR);
	  VAR
		 i: INTEGER;
   BEGIN
	  i := 0;
	  WHILE (str[i] # 0X) DO
		 PutChar(str[i]); i := i + 1
	  END;
   END Println;
   
BEGIN
   PutChar("T"); PutChar("T"); PutChar("B");
   NewLine()
END TestTool.
