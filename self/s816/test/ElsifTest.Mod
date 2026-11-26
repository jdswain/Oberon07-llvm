MODULE ElsifTest;
IMPORT SYSTEM;

VAR 
    x: INTEGER;
    
PROCEDURE PutByte(value: BYTE);
CONST
    ACIA_DATA = 0C000H;
BEGIN
    SYSTEM.PUT(0, ACIA_DATA, value);
END PutByte;

BEGIN
    (* Test ELSIF chain with different values *)
    
    (* Test 1: x = 1, should hit first condition *)
    x := 1;
    PutByte(31H);  (* '1' *)
    PutByte(3AH);  (* ':' *)
    IF x = 5 THEN
        PutByte(41H);  (* 'A' for first IF *)
    ELSIF x = 3 THEN
        PutByte(42H);  (* 'B' for first ELSIF *)
    ELSIF x = 1 THEN
        PutByte(43H);  (* 'C' for second ELSIF *)
    ELSE
        PutByte(44H);  (* 'D' for ELSE *)
    END;
    PutByte(0AH);  (* newline *)
    
    (* Test 2: x = 3, should hit second condition *)
    x := 3;
    PutByte(32H);  (* '2' *)
    PutByte(3AH);  (* ':' *)
    IF x = 5 THEN
        PutByte(41H);  (* 'A' for first IF *)
    ELSIF x = 3 THEN
        PutByte(42H);  (* 'B' for first ELSIF *)
    ELSIF x = 1 THEN
        PutByte(43H);  (* 'C' for second ELSIF *)
    ELSE
        PutByte(44H);  (* 'D' for ELSE *)
    END;
    PutByte(0AH);  (* newline *)
    
    (* Test 3: x = 7, should hit ELSE *)
    x := 7;
    PutByte(33H);  (* '3' *)
    PutByte(3AH);  (* ':' *)
    IF x = 5 THEN
        PutByte(41H);  (* 'A' for first IF *)
    ELSIF x = 3 THEN
        PutByte(42H);  (* 'B' for first ELSIF *)
    ELSIF x = 1 THEN
        PutByte(43H);  (* 'C' for second ELSIF *)
    ELSE
        PutByte(44H);  (* 'D' for ELSE *)
    END;
    PutByte(0AH);  (* newline *)
    
    PutByte(44H);  (* 'D' *)
    PutByte(6FH);  (* 'o' *)
    PutByte(6EH);  (* 'n' *)
    PutByte(65H);  (* 'e' *)
    PutByte(0AH);  (* newline *)
    
END ElsifTest.