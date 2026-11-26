MODULE ElseTest;
IMPORT SYSTEM;

VAR 
    a, b: INTEGER;
    
PROCEDURE PutByte(value: BYTE);
CONST
    ACIA_DATA = 0C000H;
BEGIN
    SYSTEM.PUT(0, ACIA_DATA, value);
END PutByte;

BEGIN
    (* Test ELSE clause with GT: 3 > 5 should go to ELSE *)
    a := 3; b := 5;
    PutByte(31H);  (* '1' *)
    PutByte(3AH);  (* ':' *)
    IF a > b THEN
        PutByte(54H);  (* 'T' for THEN *)
    ELSE
        PutByte(45H);  (* 'E' for ELSE *)
    END;
    PutByte(0AH);  (* newline *)
    
    (* Test ELSE clause with EQ: 5 = 3 should go to ELSE *)
    a := 5; b := 3;
    PutByte(32H);  (* '2' *)
    PutByte(3AH);  (* ':' *)
    IF a = b THEN
        PutByte(54H);  (* 'T' for THEN *)
    ELSE
        PutByte(45H);  (* 'E' for ELSE *)
    END;
    PutByte(0AH);  (* newline *)
    
    (* Test ELSE clause with LE: 7 <= 5 should go to ELSE *)
    a := 7; b := 5;
    PutByte(33H);  (* '3' *)
    PutByte(3AH);  (* ':' *)
    IF a <= b THEN
        PutByte(54H);  (* 'T' for THEN *)
    ELSE
        PutByte(45H);  (* 'E' for ELSE *)
    END;
    PutByte(0AH);  (* newline *)
    
    PutByte(44H);  (* 'D' *)
    PutByte(6FH);  (* 'o' *)
    PutByte(6EH);  (* 'n' *)
    PutByte(65H);  (* 'e' *)
    PutByte(0AH);  (* newline *)
    
END ElseTest.