MODULE SimpleCharTest;

VAR 
    a, b: CHAR;
    result: INTEGER;

BEGIN
    (* Test simple char comparison *)
    a := 'A';
    b := 'B';
    
    IF a < b THEN
        result := 100;
    ELSE
        result := 200;
    END;
    
END SimpleCharTest.