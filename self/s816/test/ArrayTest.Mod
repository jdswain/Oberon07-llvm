MODULE ArrayTest;
IMPORT SYSTEM;

PROCEDURE PutByte(value: BYTE);
CONST
  ACIA_DATA = 0C000H;
BEGIN
  SYSTEM.PUT(0, ACIA_DATA, value);
END PutByte;

PROCEDURE Test;
VAR
  arr: ARRAY 3 OF INTEGER;
  i: INTEGER;
BEGIN
  (* Initialize array elements *)
  arr[0] := 65;   (* ASCII 'A' *)
  arr[1] := 66;   (* ASCII 'B' *)
  arr[2] := 67;   (* ASCII 'C' *)

  (* Print array elements *)
  i := 0;
  WHILE i < 3 DO
    PutByte(arr[i]);
    i := i + 1;
  END;
END Test;

BEGIN
  Test
END ArrayTest.