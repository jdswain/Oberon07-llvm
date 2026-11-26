MODULE CmpDebugTest;
IMPORT SYSTEM;

VAR 
    i1, i2: INTEGER;
    
PROCEDURE PutByte(b: BYTE);
CONST
    ACIA_DATA = 0C000H;
BEGIN
    SYSTEM.PUT(0, ACIA_DATA, b);
END PutByte;

BEGIN
    i1 := 5; i2 := 3;
    
    (* Simple comparison test *)
    IF i1 < i2 THEN
        PutByte(54H);  (* 'T' for true - should NOT happen *)
    ELSE
        PutByte(46H);  (* 'F' for false - should happen *)
    END;
    
    PutByte(0AH);  (* newline *)
    
END CmpDebugTest.