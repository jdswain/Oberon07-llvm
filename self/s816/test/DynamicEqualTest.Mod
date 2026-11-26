MODULE DynamicEqualTest;

VAR 
    a, b: INTEGER;
    result: INTEGER;

BEGIN
    (* Test dynamic equality - different values *)
    a := 5;
    b := 3;
    
    IF a = b THEN
        result := 100;
    ELSE
        result := 200;
    END;
    
END DynamicEqualTest.