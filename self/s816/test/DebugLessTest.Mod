MODULE DebugLessTest;
IMPORT SYSTEM;

VAR 
    a, b: INTEGER;
    pass_char, fail_char, newline_char: BYTE;

PROCEDURE PutByte(b: BYTE);
CONST
    ACIA_DATA = 0C000H;
BEGIN
    SYSTEM.PUT(0, ACIA_DATA, b);
END PutByte;

BEGIN
    (* Initialize output characters *)
    pass_char := 50H;     (* 'P' *)
    fail_char := 46H;     (* 'F' *)
    newline_char := 0AH;  (* newline *)
    
    (* Test only the < operator: 5 < 3 should be false *)
    a := 5;
    b := 3;
    
    IF a < b THEN
        PutByte(fail_char);  (* Should not happen *)
    ELSE
        PutByte(pass_char);  (* Should happen *)
    END;
    PutByte(newline_char);
    
END DebugLessTest.