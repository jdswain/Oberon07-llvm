MODULE SimpleIfTest;

VAR 
    a, result: INTEGER;

BEGIN
    (* Test basic IF statement *)
    a := 5;
    
    IF a > 3 THEN
        result := 100
    END;
    
    (* Test IF statement with FALSE condition *)
    a := 1;
    
    IF a > 3 THEN
        result := 200
    END;
    
END SimpleIfTest.