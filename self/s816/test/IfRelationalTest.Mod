MODULE IfRelationalTest;

VAR 
    a, b: INTEGER;
    result: INTEGER;

BEGIN
    (* Test relational operators in IF statements *)
    a := 5;
    b := 3;
    
    IF a > b THEN
        result := 100;
    ELSE
        result := 200;
    END;
    
END IfRelationalTest.