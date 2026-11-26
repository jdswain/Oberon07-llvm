MODULE ComprehensiveCharTest;

VAR 
    a, b: CHAR;
    result1, result2, result3, result4, result5, result6: INTEGER;

BEGIN
    (* Test all CHAR relational operators *)
    a := 'C';
    b := 'A';
    
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
    
    (* Test < (should be false, so result3 = 200) *)
    IF a < b THEN
        result3 := 100;
    ELSE
        result3 := 200;
    END;
    
    (* Test <= (should be false, so result4 = 200) *)
    IF a <= b THEN
        result4 := 100;
    ELSE
        result4 := 200;
    END;
    
    (* Test > (should be true, so result5 = 100) *)
    IF a > b THEN
        result5 := 100;
    ELSE
        result5 := 200;
    END;
    
    (* Test >= (should be true, so result6 = 100) *)
    IF a >= b THEN
        result6 := 100;
    ELSE
        result6 := 200;
    END;
    
END ComprehensiveCharTest.