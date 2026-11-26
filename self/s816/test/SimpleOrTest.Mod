MODULE SimpleOrTest;

VAR 
    a, b, result: BOOLEAN;

BEGIN
    (* Test basic OR operator *)
    a := TRUE;
    b := FALSE;
    result := a OR b;  (* Should be TRUE *)
    
    a := FALSE;
    b := TRUE;
    result := a OR b;  (* Should be TRUE *)
    
    a := FALSE;
    b := FALSE;
    result := a OR b;  (* Should be FALSE *)
    
    a := TRUE;
    b := TRUE;
    result := a OR b;  (* Should be TRUE *)
    
END SimpleOrTest.