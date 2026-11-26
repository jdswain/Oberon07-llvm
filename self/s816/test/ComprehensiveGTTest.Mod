MODULE ComprehensiveGTTest;
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
    (* Test 1: Less than case - should be FALSE *)
    a := 3; b := 5;
    PutByte(31H);  (* '1' *)
    PutByte(3AH);  (* ':' *)
    IF a > b THEN
        PutByte(54H);  (* 'T' for TRUE *)
    ELSE
        PutByte(46H);  (* 'F' for FALSE *)
    END;
    PutByte(0AH);  (* newline *)
    
    (* Test 2: Equal case - should be FALSE *)
    a := 5; b := 5;
    PutByte(32H);  (* '2' *)
    PutByte(3AH);  (* ':' *)
    IF a > b THEN
        PutByte(54H);  (* 'T' for TRUE *)
    ELSE
        PutByte(46H);  (* 'F' for FALSE *)
    END;
    PutByte(0AH);  (* newline *)
    
    (* Test 3: Greater than case - should be TRUE *)
    a := 7; b := 5;
    PutByte(33H);  (* '3' *)
    PutByte(3AH);  (* ':' *)
    IF a > b THEN
        PutByte(54H);  (* 'T' for TRUE *)
    ELSE
        PutByte(46H);  (* 'F' for FALSE *)
    END;
    PutByte(0AH);  (* newline *)
    
    (* Summary *)
    PutByte(44H);  (* 'D' *)
    PutByte(6FH);  (* 'o' *)
    PutByte(6EH);  (* 'n' *)
    PutByte(65H);  (* 'e' *)
    PutByte(0AH);  (* newline *)
    
END ComprehensiveGTTest.