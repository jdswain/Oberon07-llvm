MODULE RelationalOpTest;
IMPORT SYSTEM;

VAR 
    i1, i2: INTEGER;
    c1, c2: CHAR;
    b1, b2: BOOLEAN;
    
    (* Output characters as BYTE variables like PutTest.Mod *)
    pass_char, fail_char, newline_char, test_char: BYTE;

PROCEDURE PutByte(b: BYTE);
CONST
    ACIA_DATA = 0C000H;
BEGIN
    SYSTEM.PUT(0, ACIA_DATA, b);
END PutByte;

BEGIN
    (* Initialize output characters like PutTest.Mod *)
    pass_char := 50H;     (* 'P' *)
    fail_char := 46H;     (* 'F' *)
    newline_char := 0AH;  (* newline *)
	 
    (* Test INTEGER relational operators *)
    i1 := 5; i2 := 3;
    
    (* Test = (should be false) *)
    IF i1 = i2 THEN
        PutByte(fail_char);
    ELSE
        PutByte(pass_char);
    END;
    PutByte(newline_char);  (* newline *)
    
    (* Test # (should be true) *)
    IF i1 # i2 THEN
        PutByte(pass_char);
    ELSE
        PutByte(fail_char);
    END;
    PutByte(newline_char);  (* newline *)
    
    (* Test < (should be false) *)
    IF i1 < i2 THEN
        PutByte(fail_char);
    ELSE
        PutByte(pass_char);
    END;
    PutByte(newline_char);  (* newline *)
    
    (* Test <= (should be false) *)
    IF i1 <= i2 THEN
        PutByte(fail_char);
    ELSE
        PutByte(pass_char);
    END;
    PutByte(newline_char);  (* newline *)
    
    (* Test > (should be true) *)
    IF i1 > i2 THEN
        PutByte(pass_char);
    ELSE
        PutByte(fail_char);
    END;
    PutByte(newline_char);  (* newline *)
    
    (* Test >= (should be true) *)
    IF i1 >= i2 THEN
        PutByte(pass_char);
    ELSE
        PutByte(fail_char);
    END;
    PutByte(newline_char);  (* newline *)
    
    (* Test CHAR relational operators *)
    c1 := 'Z'; c2 := 'A';
    
    (* Test CHAR = (should be false) *)
    IF c1 = c2 THEN
        PutByte(fail_char);
    ELSE
        PutByte(pass_char);
    END;
    PutByte(newline_char);  (* newline *)
    
    (* Test CHAR # (should be true) *)
    IF c1 # c2 THEN
        PutByte(pass_char);
    ELSE
        PutByte(fail_char);
    END;
    PutByte(newline_char);  (* newline *)
    
    (* Test CHAR < (should be false) *)
    IF c1 < c2 THEN
        PutByte(fail_char);
    ELSE
        PutByte(pass_char);
    END;
    PutByte(newline_char);  (* newline *)
    
    (* Test CHAR <= (should be false) *)
    IF c1 <= c2 THEN
        PutByte(fail_char);
    ELSE
        PutByte(pass_char);
    END;
    PutByte(newline_char);  (* newline *)
    
    (* Test CHAR > (should be true) *)
    IF c1 > c2 THEN
        PutByte(pass_char);
    ELSE
        PutByte(fail_char);
    END;
    PutByte(newline_char);  (* newline *)
    
    (* Test CHAR >= (should be true) *)
    IF c1 >= c2 THEN
        PutByte(pass_char);
    ELSE
        PutByte(fail_char);
    END;
    PutByte(newline_char);  (* newline *)
    
    (* Test BOOLEAN relational operators *)
    b1 := TRUE; b2 := FALSE;
    
    (* Test BOOLEAN = (should be false) *)
    IF b1 = b2 THEN
        PutByte(fail_char);
    ELSE
        PutByte(pass_char);
    END;
    PutByte(newline_char);  (* newline *)
    
    (* Test BOOLEAN # (should be true) *)
    IF b1 # b2 THEN
        PutByte(pass_char);
    ELSE
        PutByte(fail_char);
    END;
    PutByte(newline_char);  (* newline *)
    
    (* Final success message *)
    PutByte(44H);  (* 'D' *)
    PutByte(6FH);  (* 'o' *)
    PutByte(6EH);  (* 'n' *)
    PutByte(65H);  (* 'e' *)
    PutByte(newline_char);  (* newline *)
    
END RelationalOpTest.
