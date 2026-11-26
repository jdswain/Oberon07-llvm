MODULE LocalVarTest;
IMPORT SYSTEM;

PROCEDURE PutByte(value: BYTE);
CONST
  ACIA_DATA = 0C000H;
BEGIN
  SYSTEM.PUT(0, ACIA_DATA, value);
END PutByte;

PROCEDURE Inc(VAR n: INTEGER);
BEGIN
  n := n + 1;
END Inc;

PROCEDURE TestWithLocal;
VAR local: INTEGER;
BEGIN
  local := 65;        (* ASCII 'A' *)
  PutByte(local);     (* Should print 'A' *)
  Inc(local);         (* Pass local variable by reference *)
  PutByte(local);     (* Should print 'B' *)
END TestWithLocal;

BEGIN  TestWithLocal;
END LocalVarTest.
