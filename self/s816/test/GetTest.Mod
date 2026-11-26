MODULE GetTest;
IMPORT SYSTEM;

PROCEDURE Main;
CONST
    CODE_START = 2000H;
VAR
    byteValue: BYTE;
    intValue: INTEGER;
BEGIN
    SYSTEM.GET(0, CODE_START, byteValue);  (* Read first byte of code as BYTE *)
    intValue := byteValue;              (* Convert BYTE to INTEGER *)
END Main;

BEGIN
    Main
END GetTest.