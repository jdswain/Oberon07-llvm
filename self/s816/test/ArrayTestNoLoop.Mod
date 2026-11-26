MODULE ArrayTestNoLoop;
IMPORT SYSTEM;

PROCEDURE PutByte(value: INTEGER);
CONST
  ACIA_DATA = 0C000H;
BEGIN
  SYSTEM.PUT(0, ACIA_DATA, value);
END PutByte;

PROCEDURE Test;
VAR
  arr: ARRAY 3 OF INTEGER;
BEGIN
  arr[0] := 65;
  PutByte(arr[0]);
END Test;

BEGIN
  Test
END ArrayTestNoLoop.