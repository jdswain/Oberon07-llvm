MODULE SimpleNotTest;

VAR 
    a, result: BOOLEAN;

BEGIN
    (* Test basic NOT operator ~ *)
    a := TRUE;
    result := ~a;  (* Should be FALSE *)
    
    a := FALSE;
    result := ~a;  (* Should be TRUE *)
    
END SimpleNotTest.