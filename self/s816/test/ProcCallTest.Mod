MODULE ProcCallTest;

PROCEDURE Add(x: INTEGER): INTEGER;
BEGIN
    RETURN x + 1
END Add;

PROCEDURE Main;
VAR 
    a, result: INTEGER;
BEGIN
    a := 10;
    result := Add(a);
END Main;

BEGIN
    Main
END ProcCallTest.
