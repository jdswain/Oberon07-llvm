MODULE BasicRelTest;
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
    (* Test EQ: 5 = 5 should be TRUE *)
    a := 5; b := 5;
    PutByte(45H);  (* 'E' *)
    PutByte(51H);  (* 'Q' *)
    PutByte(3AH);  (* ':' *)
    IF a = b THEN
        PutByte(54H);  (* 'T' for TRUE *)
    ELSE
        PutByte(46H);  (* 'F' for FALSE *)
    END;
    PutByte(0AH);  (* newline *)
    
    (* Test NE: 3 # 5 should be TRUE *)
    a := 3; b := 5;
    PutByte(4EH);  (* 'N' *)
    PutByte(45H);  (* 'E' *)
    PutByte(3AH);  (* ':' *)
    IF a # b THEN
        PutByte(54H);  (* 'T' for TRUE *)
    ELSE
        PutByte(46H);  (* 'F' for FALSE *)
    END;
    PutByte(0AH);  (* newline *)
    
    (* Test LT: 3 < 5 should be TRUE *)
    a := 3; b := 5;
    PutByte(4CH);  (* 'L' *)
    PutByte(54H);  (* 'T' *)
    PutByte(3AH);  (* ':' *)
    IF a < b THEN
        PutByte(54H);  (* 'T' for TRUE *)
    ELSE
        PutByte(46H);  (* 'F' for FALSE *)
    END;
    PutByte(0AH);  (* newline *)
    
    (* Test GE: 7 >= 5 should be TRUE *)
    a := 7; b := 5;
    PutByte(47H);  (* 'G' *)
    PutByte(45H);  (* 'E' *)
    PutByte(3AH);  (* ':' *)
    IF a >= b THEN
        PutByte(54H);  (* 'T' for TRUE *)
    ELSE
        PutByte(46H);  (* 'F' for FALSE *)
    END;
    PutByte(0AH);  (* newline *)
    
    PutByte(44H);  (* 'D' *)
    PutByte(6FH);  (* 'o' *)
    PutByte(6EH);  (* 'n' *)
    PutByte(65H);  (* 'e' *)
    PutByte(0AH);  (* newline *)
    
END BasicRelTest.