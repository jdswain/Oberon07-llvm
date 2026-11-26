MODULE SimpleForTest;
IMPORT SYSTEM;

VAR 
    i, j: INTEGER;
    
PROCEDURE PutByte(value: BYTE);
CONST
    ACIA_DATA = 0C000H;
BEGIN
    SYSTEM.PUT(0, ACIA_DATA, value);
END PutByte;

BEGIN
    PutByte(53H);  (* 'S' *)
    PutByte(3AH);  (* ':' *)
    
    (* Very simple FOR loop from 1 to 2 *)
    FOR i := 10 TO 1 BY -1 DO
		 FOR j := 1 TO 4 DO
			  PutByte(2FH + i);  (* Convert to ASCII digit *)
		 END
    END;
    
    PutByte(0AH);  (* newline *)
    
END SimpleForTest.
