MODULE ProcedureDebug;
   IMPORT SYSTEM;
    
   PROCEDURE PutChar(value: CHAR);
	  CONST
		 ACIA_DATA = 0C000H;
   BEGIN
      SYSTEM.PUT(0, ACIA_DATA, value);
   END PutChar;

   PROCEDURE SimpleTest(x, y: INTEGER);
   BEGIN
      PutChar('P'); (* In procedure *)
      PutChar('Q'); (* Still working *)
   END SimpleTest;

BEGIN
   PutChar('S'); (* Start *)
   SimpleTest(10, -5);
   PutChar('E') (* End *)
END ProcedureDebug.