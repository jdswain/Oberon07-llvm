MODULE L18_PutChar; IMPORT Out, SYSTEM;
VAR buf: ARRAY 4 OF CHAR; c: CHAR; b: INTEGER; a: INTEGER;
BEGIN
  buf := "xyz"; a := SYSTEM.ADR(buf); b := SYSTEM.VAL(INTEGER, SYSTEM.BANK(buf));
  SYSTEM.PUT(b, a, "Q"); SYSTEM.PUT(b, a + 2, 41X);
  Out.String(buf); Out.Ln
END L18_PutChar.
