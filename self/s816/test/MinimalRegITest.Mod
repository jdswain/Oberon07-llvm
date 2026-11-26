MODULE MinimalRegITest;
  IMPORT SYSTEM;
  
  VAR
    arr: ARRAY 2 OF CHAR;
    i: INTEGER;
    
  PROCEDURE PutChar(c: CHAR);
    CONST
      ACIA_DATA = 0C000H;
  BEGIN
    SYSTEM.PUT(0, ACIA_DATA, c);
  END PutChar;
  
BEGIN
  arr[0] := 41X;  (* 'A' *)
  arr[1] := 42X;  (* 'B' *)
  
  i := 1;
  PutChar(arr[i])  (* This should trigger RegI -> value conversion *)
END MinimalRegITest.