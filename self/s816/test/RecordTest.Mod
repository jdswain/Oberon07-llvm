(* Record field access test *)
MODULE RecordTest;
   IMPORT SYSTEM;

   TYPE
      ObjDesc = RECORD
         class, exno: BYTE;
         expo, rdo: BOOLEAN;
         lev: INTEGER;
         name: ARRAY 12 OF CHAR;
         val: INTEGER
      END ;

   VAR
      obj: ObjDesc;

   PROCEDURE PutChar(value: CHAR);
      CONST
         ACIA_DATA = 0C000H;
   BEGIN
      SYSTEM.PUT(0, ACIA_DATA, value);
   END PutChar;

BEGIN
   obj.lev := 11;
   obj.name[0] := "T";
   IF obj.lev = 10 THEN
      PutChar('P')
   ELSE
      PutChar('F')
   END;
   PutChar(obj.name[0])
END RecordTest.