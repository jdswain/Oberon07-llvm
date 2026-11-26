MODULE AllRelationalOpsTest;

VAR 
    i1, i2: INTEGER;
    c1, c2: CHAR;
    b1, b2: BOOLEAN;
    result: INTEGER;

BEGIN
    (* Test all relational operators with different types *)
    i1 := 5; i2 := 3;
    c1 := 'Z'; c2 := 'A';
    b1 := TRUE; b2 := FALSE;
    
    (* INTEGER comparisons *)
    IF i1 > i2 THEN
        result := 100;
    ELSE
        result := 200;
    END;
    
    (* CHAR comparisons *)
    IF c1 >= c2 THEN
        result := 300;
    ELSE
        result := 400;
    END;
    
    (* BOOLEAN comparisons *)
    IF b1 # b2 THEN
        result := 500;
    ELSE
        result := 600;
    END;
    
    (* Mixed with complex expressions *)
    IF i1 > i2 THEN
        IF c1 >= c2 THEN
            IF b1 # b2 THEN
                result := 1000;
            ELSE
                result := 2000;
            END;
        ELSE
            result := 3000;
        END;
    ELSE
        result := 4000;
    END;
    
END AllRelationalOpsTest.