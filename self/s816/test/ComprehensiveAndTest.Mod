MODULE ComprehensiveAndTest;

VAR 
    a, b, result1, result2, result3, result4: BOOLEAN;

BEGIN
    (* Test all four combinations of AND *)
    
    (* TRUE & TRUE = TRUE *)
    a := TRUE;
    b := TRUE;
    result1 := a & b;
    
    (* TRUE & FALSE = FALSE *)
    a := TRUE;
    b := FALSE;
    result2 := a & b;
    
    (* FALSE & TRUE = FALSE *)
    a := FALSE;
    b := TRUE;
    result3 := a & b;
    
    (* FALSE & FALSE = FALSE *)
    a := FALSE;
    b := FALSE;
    result4 := a & b;
    
END ComprehensiveAndTest.