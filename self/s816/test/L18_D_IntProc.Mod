MODULE L18_D_IntProc; (* PROCEDURE* is refused *)
  IMPORT Out;
  VAR n: INTEGER;
  PROCEDURE* Isr;
  BEGIN INC(n)
  END Isr;
BEGIN Out.Int(n, 3)
END L18_D_IntProc.
