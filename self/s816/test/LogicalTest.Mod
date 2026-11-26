MODULE LogicalTest;

VAR 
    a, b, result: BOOLEAN;

BEGIN
    (* Test negation operator ~ *)
    a := TRUE;
    result := ~a;  (* Should be FALSE *)
    
    a := FALSE;
    result := ~a;  (* Should be TRUE *)
    
    (* Test logical conjunction & *)
    a := TRUE;
    b := TRUE;
    result := a & b;  (* Should be TRUE *)
    
    a := TRUE;
    b := FALSE;
    result := a & b;  (* Should be FALSE *)
    
    a := FALSE;
    b := TRUE;
    result := a & b;  (* Should be FALSE *)
    
    a := FALSE;
    b := FALSE;
    result := a & b;  (* Should be FALSE *)
    
    (* Test logical disjunction OR *)
    a := TRUE;
    b := TRUE;
    result := a OR b;  (* Should be TRUE *)
    
    a := TRUE;
    b := FALSE;
    result := a OR b;  (* Should be TRUE *)
    
    a := FALSE;
    b := TRUE;
    result := a OR b;  (* Should be TRUE *)
    
    a := FALSE;
    b := FALSE;
    result := a OR b   (* Should be FALSE *)
END LogicalTest.