MODULE OpTest;
   VAR
	  a, b, c: INTEGER;
BEGIN
   b := 000FH;
   c := 00F0H;
   a := ORA(b, c);
END OpTest.