MODULE ArrayProcTest;
   IMPORT SYSTEM;
	  
   VAR
	  arr: ARRAY 3 OF BYTE;
	  x: BYTE;
	  
   PROCEDURE PutByte(value: BYTE);
	  CONST
		 ACIA_DATA = 0C000H;
   BEGIN
	  SYSTEM.PUT(0, ACIA_DATA, value);
   END PutByte;
   
   PROCEDURE PutArr(a: ARRAY OF BYTE);
	  VAR
		 i: INTEGER;
   BEGIN
	  FOR i := 0 TO 3 DO
		 PutByte(a[i]);
	  END
   END PutArr;
   
BEGIN
   arr[0] := 65;   (* ASCII 'A' *)
   arr[1] := 66;   (* ASCII 'B' *)
   arr[2] := 67;   (* ASCII 'C' *)
   x := arr[2];
   PutArr(arr)
END ArrayProcTest.
