MODULE SimpleLessEqualTest;

VAR 
    a, b: INTEGER;
    result: INTEGER;

BEGIN
    (* Test simple less than or equal *)
    a := 3;
    b := 5;
    
    IF a <= b THEN
        result := 100;
    ELSE
        result := 200;
    END;
    
END SimpleLessEqualTest.