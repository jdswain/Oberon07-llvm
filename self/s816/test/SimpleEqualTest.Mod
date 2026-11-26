MODULE SimpleEqualTest;

VAR 
    a, b: INTEGER;
    result: INTEGER;

BEGIN
    (* Test simple equality - should be easier to debug *)
    a := 5;
    b := 5;
    
    IF a = b THEN
        result := 100;
    ELSE
        result := 200;
    END;
    
END SimpleEqualTest.