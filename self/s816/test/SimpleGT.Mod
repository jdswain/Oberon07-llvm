MODULE SimpleGTTest;
IMPORT SYSTEM;

VAR 
    a, b: INTEGER;
    
PROCEDURE PutChar(value: CHAR);
CONST
    ACIA_DATA = 0C000H;
BEGIN
    SYSTEM.PUT(0, ACIA_DATA, value);
END PutChar;

BEGIN
    (* Test 2: Equal case - should be FALSE *)
    a := 5; b := 5;
    PutChar('2');
    PutChar(':');
    IF a > b THEN
        PutChar('T');
    ELSE
        PutChar('F');
    END;
    (* PutChar(0AH);  ( * newline *)
END SimpleGTTest.
