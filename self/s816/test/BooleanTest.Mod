MODULE BooleanTest;
  IMPORT SYSTEM;

  CONST
    ACIA_DATA = 0C000H;
 VAR
	b: BOOLEAN;
	i: INTEGER;
	
 PROCEDURE PutChar(value: CHAR);
 BEGIN
    SYSTEM.PUT(0, ACIA_DATA, value);
 END PutChar;
 
 PROCEDURE NewLine();
 BEGIN
    SYSTEM.PUT(0, ACIA_DATA, 0AX);
 END NewLine;
 
BEGIN
   PutChar('*');
   b := FALSE;
   i := 0;
   WHILE ~b DO
	  PutChar('T');
	  INC(i);
	  IF i = 3 THEN b := TRUE; END;
   END;
  NewLine();
END BooleanTest.