MODULE BranchTest;
  IMPORT SYSTEM;

  CONST
    ACIA_DATA = 0C000H;
    
  PROCEDURE PutChar(value: CHAR);
  BEGIN
    SYSTEM.PUT(0, ACIA_DATA, value);
  END PutChar;

  PROCEDURE TestBranch(x: INTEGER);
  BEGIN
	 IF x > 5 THEN
      PutChar('T')
    ELSE
      PutChar('F')
    END;
    PutChar('E')

  END TestBranch;

BEGIN
  TestBranch(3);
  TestBranch(7);
  PutChar(0AX);  (* newline *)
END BranchTest.