MODULE StringCopyTest;
   (* Test string copy functionality *)
   
   IMPORT SYSTEM;

   VAR
      source: ARRAY 20 OF CHAR;
      dest: ARRAY 20 OF CHAR;
    
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
   
BEGIN
   source := "Hello World";
   dest := source;  (* This should trigger ORG_CopyString *)
   WriteString(dest);
END StringCopyTest.