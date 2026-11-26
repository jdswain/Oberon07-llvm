MODULE L18_D_SysH; (* SYSTEM.H is refused *)
  IMPORT SYSTEM, Out;
  VAR i: INTEGER;
BEGIN i := SYSTEM.H(0); Out.Int(i, 3)
END L18_D_SysH.
