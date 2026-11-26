MODULE RelationalTest;

VAR 
    a, b: INTEGER;
    result: BOOLEAN;

BEGIN
    (* Test basic relational operators *)
    a := 5;
    b := 3;
    
    result := a > b;  (* Should be TRUE *)
    result := a < b;  (* Should be FALSE *)
    result := a = b;  (* Should be FALSE *)
    result := a # b;  (* Should be TRUE *)
    
END RelationalTest.