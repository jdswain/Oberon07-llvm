MODULE SimpleLessTest;

VAR 
    a, b: INTEGER;
    result: INTEGER;

BEGIN
    (* Test simple less than *)
    a := 30;
    b := 5;
    
    IF a < b THEN
        result := 100;
    ELSE
        result := 200;
    END;
    
END SimpleLessTest.
