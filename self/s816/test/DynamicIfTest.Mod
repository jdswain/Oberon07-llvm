MODULE DynamicIfTest;

VAR 
    a, b: BOOLEAN;
    result: INTEGER;

BEGIN
    (* Test IF with dynamic condition *)
    a := TRUE;
    b := FALSE;
    
    IF a & b THEN
        result := 100;
    ELSE
        result := 200;
    END;
    
    (* Test another dynamic condition *)
    IF a OR b THEN
        result := 300;
    ELSE
        result := 400;
    END;
    
END DynamicIfTest.