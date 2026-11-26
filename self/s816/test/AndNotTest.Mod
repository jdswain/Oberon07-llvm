MODULE AndNotTest;

VAR 
    a, b, result: BOOLEAN;

BEGIN
    (* Test AND with NOT: ~a & b *)
    a := TRUE;
    b := FALSE;
    result := ~a & b;  (* Should be FALSE & FALSE = FALSE *)
    
    (* Test AND with NOT: a & ~b *)
    a := TRUE;
    b := FALSE;
    result := a & ~b;  (* Should be TRUE & TRUE = TRUE *)
    
END AndNotTest.