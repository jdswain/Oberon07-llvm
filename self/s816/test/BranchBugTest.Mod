MODULE BranchBugTest;

VAR result: INTEGER;

PROCEDURE TestProc(condition: BOOLEAN): INTEGER;
VAR r: INTEGER;
BEGIN
    IF condition THEN
        r := 100
    ELSE
        r := 200
    END;
    RETURN r
END TestProc;

BEGIN
    result := TestProc(TRUE);
    result := TestProc(FALSE)
END BranchBugTest.