MODULE AllBooleanOpsTest;

VAR 
    a, b, c, result: BOOLEAN;

BEGIN
    (* Test complex expressions with all boolean operators *)
    
    (* Test: NOT and AND: ~a & b *)
    a := TRUE;
    b := FALSE;
    result := ~a & b;  (* Should be FALSE & FALSE = FALSE *)
    
    (* Test: AND and OR: (a & b) OR c *)
    a := FALSE;
    b := TRUE;
    c := TRUE;
    result := (a & b) OR c;  (* Should be FALSE OR TRUE = TRUE *)
    
    (* Test: Complex expression: ~(a OR b) & c *)
    a := FALSE;
    b := FALSE;
    c := TRUE;
    result := ~(a OR b) & c;  (* Should be ~FALSE & TRUE = TRUE & TRUE = TRUE *)
    
END AllBooleanOpsTest.