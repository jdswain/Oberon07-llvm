MODULE SimpleVarTest;
IMPORT SYSTEM;

VAR 
  x: INTEGER;
    
PROCEDURE PutByte(value: BYTE);
CONST
  ACIA_DATA = 0C000H;
BEGIN
  SYSTEM.PUT(0, ACIA_DATA, value);
END PutByte;

PROCEDURE Inc2(VAR n: INTEGER);
BEGIN
  n := n + 1;
END Inc2;

PROCEDURE Inc1(VAR n: INTEGER);
BEGIN
  Inc2(n);
END Inc1;

BEGIN
  x := 65;         (* ASCII 'A' *)
  PutByte(x);      (* Should print 'A' *)
  Inc1(x);         (* Pass x by reference *)
  PutByte(x);      (* Should print 'B' *)
END SimpleVarTest.
