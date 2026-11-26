MODULE VarParamTest;
IMPORT SYSTEM;

VAR 
  globalVar: INTEGER;
    
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

PROCEDURE ModifyVar(VAR x: INTEGER);
BEGIN
  x := x + 1;
END ModifyVar;

BEGIN
  PutByte(56H);  (* V *)
  PutByte(3AH);  (* : *)
  
  (* Test VAR parameter with module global variable *)
  globalVar := 5;
  PutNum(globalVar);  (* Should print 5 *)
  
  ModifyVar(globalVar);  (* Pass global var by reference *)
  PutNum(globalVar);     (* Should print 6 *)
  
  PutByte(0AH);  (* newline *)
END VarParamTest.