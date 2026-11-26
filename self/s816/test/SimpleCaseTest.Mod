MODULE SimpleCaseTest;
IMPORT SYSTEM;

VAR 
  i: INTEGER;
    
PROCEDURE PutByte(value: BYTE);
CONST
  ACIA_DATA = 0C000H;
BEGIN
  SYSTEM.PUT(0, ACIA_DATA, value);
END PutByte;

BEGIN
  i := 2;
  CASE i OF
    1: PutByte(41H);  (* A *)
  | 2: PutByte(42H);  (* B *)
  END;
END SimpleCaseTest.
