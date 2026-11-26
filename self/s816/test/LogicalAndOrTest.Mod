MODULE LogicalAndOrTest;

VAR 
    a, b, result: BOOLEAN;

BEGIN
    (* Test logical AND - all four combinations *)
    a := FALSE;
    b := TRUE;
    result := a & b;  (* Should be TRUE *)

    (*
    a := TRUE;
    b := FALSE;
    result := a & b;  (* Should be FALSE *)
    
    a := FALSE;
    b := TRUE;
    result := a & b;  (* Should be FALSE *)
    
    a := FALSE;
    b := FALSE;
    result := a & b;  (* Should be FALSE *)
    
    (* Test logical OR - all four combinations *)
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
	*)
END LogicalAndOrTest.
