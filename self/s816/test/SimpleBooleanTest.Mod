MODULE SimpleBooleanTest;

VAR 
    a, b: BOOLEAN;
    result1, result2: INTEGER;

BEGIN
    (* Test BOOLEAN relational operators *)
    a := TRUE;
    b := FALSE;
    
    (* Test = (should be false, so result1 = 200) *)
    IF a = b THEN
        result1 := 100;
    ELSE
        result1 := 200;
    END;
    
    (* Test # (should be true, so result2 = 100) *)
    IF a # b THEN
        result2 := 100;
    ELSE
        result2 := 200;
    END;
    
END SimpleBooleanTest.