MODULE ReturnTest;
  IMPORT SYSTEM;

  CONST
    ACIA_DATA = 0C000H;
    
  PROCEDURE PutChar(value: CHAR);
  BEGIN
    SYSTEM.PUT(0, ACIA_DATA, value);
  END PutChar;

  PROCEDURE Add(a, b: INTEGER): INTEGER;
  BEGIN
    PutChar('A');
    RETURN a + b
  END Add;
  
  PROCEDURE TestReturn;
    VAR result, x: INTEGER;
  BEGIN
     PutChar('S');
	 x := 2;
    result := x + Add(5, 3);
	IF result = 10 THEN
       PutChar('T');
	END;
    PutChar('E');
    RETURN
  END TestReturn;

BEGIN
   TestReturn;
  PutChar(0AX);  (* newline *)
END ReturnTest.