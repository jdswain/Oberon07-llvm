MODULE SimpleRegIDebugTest;
  IMPORT SYSTEM;
  
  VAR
    arr: ARRAY 3 OF CHAR;
    i: INTEGER;
    
  PROCEDURE PutChar(c: CHAR);
    CONST
      ACIA_DATA = 0C000H;
  BEGIN
    SYSTEM.PUT(0, ACIA_DATA, c);
  END PutChar;
  
BEGIN
  (* Initialize array *)
  arr[0] := "A";
  arr[1] := "B";
  arr[2] := "C";
  
  (* Test constant indexing first *)
  PutChar(arr[0]);  (* Should output 'A' *)
  PutChar(arr[1]);  (* Should output 'B' *)
  
  (* Test variable indexing *)
  i := 2;
  PutChar(arr[i]);  (* Should output 'C' using RegI dereferencing *)
  
END SimpleRegIDebugTest.