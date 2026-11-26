MODULE IfWithNotTest;

VAR 
    condition: BOOLEAN;
    result: INTEGER;

BEGIN
    (* Test IF statement with NOT operator *)
    condition := TRUE;
    
    IF ~condition THEN
        result := 100;
    END;
    
    (* This should execute *)
    condition := FALSE;
    
    IF ~condition THEN
        result := 200;
    END;
    
END IfWithNotTest.