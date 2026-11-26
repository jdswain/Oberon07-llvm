MODULE LocalVarParamTest;
IMPORT SYSTEM;

PROCEDURE PutByte(value: BYTE);
CONST
  ACIA_DATA = 0C000H;
BEGIN
  SYSTEM.PUT(0, ACIA_DATA, value);
END PutByte;

PROCEDURE PutNum(n: INTEGER);
BEGIN
  PutByte(30H + n);  (* Convert to ASCII digit *)
END PutNum;

PROCEDURE ModifyLocal(VAR x: INTEGER);
BEGIN
  x := x + 1;
END ModifyLocal;

PROCEDURE TestLocalVar;
VAR localVar: INTEGER;
BEGIN
  PutByte(4CH);  (* L *)
  PutByte(3AH);  (* : *)
  
  localVar := 3;
  PutNum(localVar);        (* Should print 3 *)
  ModifyLocal(localVar);   (* Pass local var by reference *)
  PutNum(localVar);        (* Should print 4 *)
  
  PutByte(0AH);  (* newline *)
END TestLocalVar;

BEGIN
  TestLocalVar;
END LocalVarParamTest.