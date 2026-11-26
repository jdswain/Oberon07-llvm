MODULE SimpleGreaterEqualTest;

VAR 
    a, b: INTEGER;
    result: INTEGER;

BEGIN
    (* Test simple greater than or equal *)
    a := 5;
    b := 3;
    
    IF a >= b THEN
        result := 100;
    ELSE
        result := 200;
    END;
    
END SimpleGreaterEqualTest.