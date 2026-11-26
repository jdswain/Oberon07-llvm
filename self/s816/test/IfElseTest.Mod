MODULE IfElseTest;

VAR 
    condition: BOOLEAN;
    result: INTEGER;

BEGIN
    (* Test IF-ELSE statement *)
    condition := TRUE;
    
    IF condition THEN
        result := 100;
    ELSE
        result := 200;
    END;
    
    (* Test IF-ELSE with FALSE condition *)
    condition := FALSE;
    
    IF condition THEN
        result := 300;
    ELSE
        result := 400;
    END;
    
END IfElseTest.