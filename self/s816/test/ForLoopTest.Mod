MODULE ForLoopTest;
IMPORT SYSTEM;

VAR 
    i: INTEGER;
    
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

BEGIN
    PutByte(46H);  (* 'F' *)
    PutByte(4FH);  (* 'O' *)
    PutByte(52H);  (* 'R' *)
    PutByte(3AH);  (* ':' *)

    (* Simple FOR loop from 1 to 3 *)
    FOR i := 1 TO 3 DO
        PutNum(i);
        PutByte(20H);  (* space *)
    END;
    
    PutByte(0AH);  (* newline *)
    PutByte(44H);  (* 'D' *)
    PutByte(6FH);  (* 'o' *)
    PutByte(6EH);  (* 'n' *)
    PutByte(65H);  (* 'e' *)
    PutByte(0AH);  (* newline *)
    
END ForLoopTest.
