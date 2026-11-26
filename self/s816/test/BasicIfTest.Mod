MODULE BasicIfTest;

VAR 
    condition: BOOLEAN;
    result: INTEGER;

BEGIN
    (* Test basic IF statement with boolean variable *)
    condition := TRUE;
    
    IF condition THEN
        result := 100;
    END;
    
    (* Test IF statement with FALSE condition *)
    condition := FALSE;
    
    IF condition THEN
        result := 200;
    END;
    
END BasicIfTest.